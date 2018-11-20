//
//  AdamantAccountService.swift
//  Adamant
//
//  Created by Anokhov Pavel on 07.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation
import Lisk

class AdamantAccountService: AccountService {
	
	// MARK: Dependencies
	
	var apiService: ApiService!
	var adamantCore: AdamantCore!
	var notificationsService: NotificationsService!
	var securedStore: SecuredStore! {
		didSet {
			securedStoreSemaphore.wait()
			defer {
				securedStoreSemaphore.signal()
			}
            
            if securedStore.get(.mainAccount) != nil {
                hasStayInAccount = true
                _useBiometry = securedStore.get(.useBiometry) != nil
            } else if securedStore.get(.passphrase) != nil {
                hasStayInAccount = true
                _useBiometry = securedStore.get(.useBiometry) != nil
            } else if securedStore.get(.publicKey) != nil,
				securedStore.get(.privateKey) != nil,
				securedStore.get(.pin) != nil {
				hasStayInAccount = true
				
				_useBiometry = securedStore.get(.useBiometry) != nil
			} else {
				hasStayInAccount = false
				_useBiometry = false
			}
		}
	}
	
	
	// MARK: Properties
	
	private(set) var state: AccountServiceState = .notLogged
	private let stateSemaphore = DispatchSemaphore(value: 1)
	private let securedStoreSemaphore = DispatchSemaphore(value: 1)
	
	private(set) var account: AdamantAccount?
	private(set) var keypair: Keypair?
	private var passphrase: String?
    
    private var mainAccount: LocalAdamantAccount?
	
	private func setState(_ state: AccountServiceState) {
		stateSemaphore.wait()
		self.state = state
		stateSemaphore.signal()
	}
	
	private(set) var hasStayInAccount: Bool = false
	
	private var _useBiometry: Bool = false
	var useBiometry: Bool {
		get {
			return _useBiometry
		}
		set {
			securedStoreSemaphore.wait()
			defer {
				securedStoreSemaphore.signal()
			}
			
			guard hasStayInAccount else {
				_useBiometry = false
				return
			}
			
			_useBiometry = newValue
			
			if newValue {
				securedStore.set(String(useBiometry), for: .useBiometry)
			} else {
				securedStore.remove(.useBiometry)
			}
		}
	}
	
	// MARK: Wallets
	var wallets: [WalletService] = [
		AdmWalletService(),
		try! EthWalletService(apiUrl: AdamantResources.ethServers.first!), // TODO: Move to background thread
//		LskWalletService()
	]
}

// MARK: - Saved data
extension AdamantAccountService {
	func setStayLoggedIn(pin: String, completion: @escaping (AccountServiceResult) -> Void) {
		guard let account = account, let keypair = keypair else {
			completion(.failure(.userNotLogged))
			return
		}
		
		securedStoreSemaphore.wait()
		defer {
			securedStoreSemaphore.signal()
		}
		
		if hasStayInAccount {
			completion(.failure(.internalError(message: "Already has account", error: nil)))
			return
		}
		
		securedStore.set(pin, for: .pin)
		
		if let passphrase = passphrase {
            mainAccount = LocalAdamantAccount(name: String.adamantLocalized.multiAccount.mainAccount, address: account.address, passphrase: passphrase, keyPair: keypair)
            
            if let account = mainAccount {
                _ = securedStore.saveMainAccount(account)
            } else {
                securedStore.set(passphrase, for: .passphrase)
            }
		} else {
			securedStore.set(keypair.publicKey, for: .publicKey)
			securedStore.set(keypair.privateKey, for: .privateKey)
		}
		
		hasStayInAccount = true
		NotificationCenter.default.post(name: Notification.Name.AdamantAccountService.stayInChanged, object: self, userInfo: [AdamantUserInfoKey.AccountService.newStayInState : true])
		completion(.success(account: account, alert: nil))
	}
    
    func addAccount(name: String, passphrase: String, completion: @escaping (AccountSavingResult) -> Void) {
        guard AdamantUtilities.validateAdamantPassphrase(passphrase: passphrase) else {
            completion(.failure(.invalidPassphrase))
            return
        }
        
        guard let keypair = adamantCore.createKeypairFor(passphrase: passphrase) else {
            completion(.failure(.internalError(message: "Failed to generate keypair for passphrase", error: nil)))
            return
        }
        
        var additionalAccounts = securedStore.getAdditionalAccounts()
        let address = getAddress(from: keypair.publicKey)
        
        guard getMainAccount()?.address != address else {
            completion(.failure(.internalError(message: "Already logined in this account", error: nil)))
            return
        }
        let account = LocalAdamantAccount(name: name, address: address, passphrase: passphrase, keyPair: keypair)
        
        if additionalAccounts[address] == nil {
            additionalAccounts[address] = account
        } else {
            completion(.failure(.internalError(message: "Already logined in this account", error: nil)))
            return
        }
        
        do {
            let jsonData = try JSONEncoder().encode(additionalAccounts)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                securedStore.set(jsonString, for: .additionalAccounts)
                switchToAccount(address: account.address) { (result) in
                    completion(.success(account: account, alert: nil))
                }
            } else {
                print("Fail save additionl accounts to secure storege")
                completion(.failure(.internalError(message: "Fail save additionl accounts to secure storege", error: nil)))
            }
        } catch let err {
            print("Fail save additionl accounts to secure storege with error: ", err)
            completion(.failure(.internalError(message: "Fail save additionl accounts to secure storege with error:", error: err)))
        }
    }
    
    func getAccounts() -> [String : LocalAdamantAccount] {
        var accounts = [String : LocalAdamantAccount]()
        
        if let main = getMainAccount() {
            accounts[main.address] = main
        }
        let additionalAccounts = securedStore.getAdditionalAccounts()
        accounts.merge(additionalAccounts) { (curent, new) -> LocalAdamantAccount in curent }
        
        return accounts
    }
    
    func getMainAccount() -> LocalAdamantAccount? {
        if mainAccount != nil {
            return mainAccount
        }
        
        if let mainAccount = securedStore.getMainAccount() {
            self.mainAccount = mainAccount
            return self.mainAccount
        }
        
        guard let passphrase = securedStore.get(Key.passphrase) else {
            return nil
        }
        
        guard AdamantUtilities.validateAdamantPassphrase(passphrase: passphrase) else {
            return nil
        }
        
        guard let keypair = adamantCore.createKeypairFor(passphrase: passphrase) else {
            return nil
        }
        
        let address = getAddress(from: keypair.publicKey)
        mainAccount = LocalAdamantAccount(name: String.adamantLocalized.multiAccount.mainAccount, address: address, passphrase: passphrase, keyPair: keypair)
        
        if let account = mainAccount {
            _ = securedStore.saveMainAccount(account)
        }
        
        return mainAccount
    }
    
    func getAdditionalAccounts() -> [String : LocalAdamantAccount] {
        return securedStore.getAdditionalAccounts()
    }
    
    func removeAdditionalAccounts(address: String, completion: @escaping (AccountServiceResult) -> Void) {
        var additionalAccounts = securedStore.getAdditionalAccounts()
        additionalAccounts.removeValue(forKey: address)
        
        if securedStore.saveAdditionalAccounts(additionalAccounts) {
            if address == account?.address {
                switchToAccount(address: getMainAccount()?.address ?? "", completion: completion)
            }
            
            if let account = account {
                completion(.success(account: account, alert: nil))
            } else {
                completion(.failure(.internalError(message: "Fail save additionl accounts to secure storege", error: nil)))
            }
        } else {
            completion(.failure(.internalError(message: "Fail save additionl accounts to secure storege", error: nil)))
        }
    }
    
    func dropAdditionalAccounts() {
        securedStore.remove(.lastUsedAccount)
        securedStore.remove(.additionalAccounts)
        
        
        if let main = getMainAccount(), main.passphrase != passphrase {
            switchToAccount(address: main.address) { (result) in
                //
            }
        }
    }
    
    func switchToAccount(address: String, completion: @escaping (AccountServiceResult) -> Void) {
        let accounts = getAccounts()
        if let account = accounts[address] {
            loginWith(passphrase: account.passphrase, stayIn: true) { (result) in
                self.securedStore.set(address, for: .lastUsedAccount)
                completion(result)
            }
        }
    }
    
    func getAllUnreaded() -> Int {
        return securedStore.getAllUnreaded()
    }
    
    func setUnreadedChats(_ value: Int) {
        guard let address = self.account?.address, var account = securedStore.getAccount(by: address) else {
            print("Fail to save unreaded for current account")
            return
        }
        
        account.chatProvider.notifiedCount = value
        securedStore.updateAccount(account)
    }
    
    /// Extract Adamant address from a public key
    func getAddress(from publicKey: String) -> String {
        let bytes = SHA256(publicKey.hexBytes()).digest()
        let identifier = byteIdentifier(from: bytes)
        return "U\(identifier)"
    }
    
    func byteIdentifier(from bytes: [UInt8]) -> String {
        guard bytes.count >= 8 else { return "" }
        let leadingBytes = bytes[0..<8].reversed()
        let data = Data(bytes: Array(leadingBytes))
        let value = UInt64(bigEndian: data.withUnsafeBytes { $0.pointee })
        return "\(value)"
    }
	
	func validatePin(_ pin: String) -> Bool {
		guard let savedPin = securedStore.get(.pin) else {
			return false
		}
		
		return pin == savedPin
	}
	
	private func getSavedKeypair() -> Keypair? {
		if let publicKey = securedStore.get(.publicKey), let privateKey = securedStore.get(.privateKey) {
			return Keypair(publicKey: publicKey, privateKey: privateKey)
		}
		
		return nil
	}
	
	private func getSavedPassphrase() -> String? {
        if let main = getMainAccount() {
            return main.passphrase
        }
        
		return securedStore.get(.passphrase)
	}
	
	func dropSavedAccount() {
		securedStoreSemaphore.wait()
		defer {
			securedStoreSemaphore.signal()
		}
		
		_useBiometry = false
		securedStore.remove(.pin)
		securedStore.remove(.publicKey)
		securedStore.remove(.privateKey)
		securedStore.remove(.useBiometry)
		securedStore.remove(.passphrase)
        
        securedStore.remove(.mainAccount)
        
        dropAdditionalAccounts()
        
		hasStayInAccount = false
		NotificationCenter.default.post(name: Notification.Name.AdamantAccountService.stayInChanged, object: self, userInfo: [AdamantUserInfoKey.AccountService.newStayInState : false])
		notificationsService.setNotificationsMode(.disabled, completion: nil)
	}
}


// MARK: - AccountService
extension AdamantAccountService {
	// MARK: Update logged account info
    func update() {
        self.update(nil)
    }
    
	func update(_ completion: ((AccountServiceResult) -> Void)?) {
		stateSemaphore.wait()
		
		switch state {
		case .notLogged, .isLoggingIn, .updating:
			stateSemaphore.signal()
			return
			
		case .loggedIn:
			break
		}
		
		let prevState = state
		state = .updating
		stateSemaphore.signal()
		
		guard let loggedAccount = account else {
			return
		}
		
		apiService.getAccount(byPublicKey: loggedAccount.publicKey) { [weak self] result in
			switch result {
			case .success(let account):
				guard let acc = self?.account, acc.address == account.address else {
					// User has logged out, we not interested anymore
					self?.setState(.notLogged)
					return
				}
				
				if loggedAccount.balance != account.balance {
					self?.account = account
					NotificationCenter.default.post(name: Notification.Name.AdamantAccountService.accountDataUpdated, object: self)
				}
				
				self?.setState(.loggedIn)
				completion?(.success(account: account, alert: nil))
				
				if let adm = self?.wallets.first(where: { $0 is AdmWalletService }) {
					adm.update()
				}
				
			case .failure(let error):
                completion?(.failure(.apiError(error: error)))
				self?.setState(prevState)
			}
		}
		
		for wallet in wallets.filter({ !($0 is AdmWalletService) }) {
			wallet.update()
		}
	}
}


// MARK: - Creating account
extension AdamantAccountService {
	// MARK: passphrase
	func createAccountWith(passphrase: String, completion: @escaping (AccountServiceResult) -> Void) {
		guard AdamantUtilities.validateAdamantPassphrase(passphrase: passphrase) else {
			completion(.failure(.invalidPassphrase))
			return
		}
		
		guard let publicKey = adamantCore.createKeypairFor(passphrase: passphrase)?.publicKey else {
			completion(.failure(.internalError(message: "Can't create key for passphrase", error: nil)))
			return
		}
		
		self.apiService.getAccount(byPublicKey: publicKey) { [weak self] result in
			switch result {
			case .success(_):
				completion(.failure(.wrongPassphrase))
				
			case .failure(_):
				if let apiService = self?.apiService {
					apiService.newAccount(byPublicKey: publicKey) { result in
						switch result {
						case .success(let account):
							completion(.success(account: account, alert: nil))
							
						case .failure(let error):
							completion(.failure(.apiError(error: error)))
						}
					}
				} else {
					completion(.failure(.internalError(message: "A bad thing happened", error: nil)))
				}
			}
		}
	}
}

// MARK: - Log In
extension AdamantAccountService {
	// MARK: Passphrase
    func loginWith(passphrase: String, completion: @escaping (AccountServiceResult) -> Void) {
        self.loginWith(passphrase: passphrase, stayIn: false, completion: completion)
    }
    
    func loginWith(passphrase: String, stayIn: Bool, completion: @escaping (AccountServiceResult) -> Void) {
		guard AdamantUtilities.validateAdamantPassphrase(passphrase: passphrase) else {
			completion(.failure(.invalidPassphrase))
			return
		}
		
		guard let keypair = adamantCore.createKeypairFor(passphrase: passphrase) else {
			completion(.failure(.internalError(message: "Failed to generate keypair for passphrase", error: nil)))
			return
		}
		
        loginWith(keypair: keypair, stayIn: stayIn) { [weak self] result in
			guard case .success = result else {
				completion(result)
				return
			}
			
			// MARK: Drop saved accs
            if !stayIn {
                if let storedPassphrase = self?.getSavedPassphrase(), storedPassphrase != passphrase {
                    self?.dropSavedAccount()
                }
                
                if let storedKeypair = self?.getSavedKeypair(), storedKeypair != self?.keypair {
                    self?.dropSavedAccount()
                }
            }
			
			// Update and initiate wallet services
			self?.passphrase = passphrase
			
			if let wallets = self?.wallets {
				for case let wallet as InitiatedWithPassphraseService in wallets {
					wallet.initWallet(withPassphrase: passphrase, completion: { _ in })
				}
			}
			
			completion(result)
		}
	}
	
	// MARK: Pincode
	func loginWith(pincode: String, completion: @escaping (AccountServiceResult) -> Void) {
		guard let storePin = securedStore.get(.pin) else {
			completion(.failure(.invalidPassphrase))
			return
		}
		
		guard storePin == pincode else {
			completion(.failure(.invalidPassphrase))
			return
		}
		
		loginWithStoredAccount(completion: completion)
	}
	
	// MARK: Biometry
	func loginWithStoredAccount(completion: @escaping (AccountServiceResult) -> Void) {
		if let passphrase = getSavedPassphrase() {
            if let address = securedStore.get(.lastUsedAccount) {
                let accounts = securedStore.getAdditionalAccounts()
                if let lastUsedAccount = accounts[address] {
                    loginWith(passphrase: lastUsedAccount.passphrase, stayIn: true, completion: completion)
                    return
                }
            }
			loginWith(passphrase: passphrase, completion: completion)
			return
		}
		
		if let keypair = getSavedKeypair() {
			loginWith(keypair: keypair) { result in
				switch result {
				case .success(let account, _):
					completion(.success(account: account,
										alert: (title: String.adamantLocalized.accountService.updateAlertTitleV12,
												message: String.adamantLocalized.accountService.updateAlertMessageV12)))
					
				default:
					completion(result)
				}
			}
			return
		}
		
		completion(.failure(.invalidPassphrase))
	}
	
	
	// MARK: Keypair
    private func loginWith(keypair: Keypair, completion: @escaping (AccountServiceResult) -> Void) {
        self.loginWith(keypair: keypair, stayIn: false, completion: completion)
    }
    
    private func loginWith(keypair: Keypair, stayIn: Bool, completion: @escaping (AccountServiceResult) -> Void) {
		stateSemaphore.wait()
		switch state {
		case .isLoggingIn:
			stateSemaphore.signal()
			completion(.failure(.internalError(message: "Service is busy", error: nil)))
			return
			
		case .updating:
			fallthrough
			
		// Logout first
		case .loggedIn:
            logout(lockSemaphore: false, stayIn: stayIn)
			
		// Go login
		case .notLogged:
			break
		}
		
		state = .isLoggingIn
		stateSemaphore.signal()
		
		apiService.getAccount(byPublicKey: keypair.publicKey) { result in
			switch result {
			case .success(let account):
				self.account = account
				self.keypair = keypair
				
				let userInfo = [AdamantUserInfoKey.AccountService.loggedAccountAddress:account.address]
				NotificationCenter.default.post(name: Notification.Name.AdamantAccountService.userLoggedIn, object: self, userInfo: userInfo)
				self.setState(.loggedIn)
				
				completion(.success(account: account, alert: nil))
				
			case .failure(let error):
				self.setState(.notLogged)
				switch error {
				case .accountNotFound:
					completion(.failure(.wrongPassphrase))
					
				default:
					completion(.failure(.apiError(error: error)))
				}
			}
		}
	}
}


// MARK: - Log Out
extension AdamantAccountService {
	func logout() {
		logout(lockSemaphore: true)
	}
	
    private func logout(lockSemaphore: Bool, stayIn: Bool = false) {
		if account != nil {
			NotificationCenter.default.post(name: Notification.Name.AdamantAccountService.userWillLogOut, object: self)
		}
		
        if !stayIn {
            dropSavedAccount()
        }
		
		let wasLogged = account != nil
		account = nil
		keypair = nil
		passphrase = nil
		
		if lockSemaphore {
			setState(.notLogged)
		} else {
			state = .notLogged
		}
		
		if wasLogged {
            NotificationCenter.default.post(name: Notification.Name.AdamantAccountService.userLoggedOut, object: self, userInfo: ["stayIn": stayIn])
		}
	}
}

// MARK: - Secured Store
extension StoreKey {
	fileprivate struct accountService {
		static let publicKey = "accountService.publicKey"
		static let privateKey = "accountService.privateKey"
		static let pin = "accountService.pin"
		static let useBiometry = "accountService.useBiometry"
		static let passphrase = "accountService.passphrase"
        
        static let mainAccount = "accountService.mainAccount"
        static let lastUsedAccount = "accountService.lastUsedAccount"
        static let additionalAccounts = "accountService.additionalAccounts"
        
        static let addressPool = "accountService.addressPool"
		
		private init() {}
	}
}

fileprivate enum Key {
	case publicKey
	case privateKey
	case pin
	case useBiometry
	case passphrase
    
    case mainAccount
    case lastUsedAccount
    case additionalAccounts
    
    case addressPool
	
	var stringValue: String {
		switch self {
		case .publicKey: return StoreKey.accountService.publicKey
		case .privateKey: return StoreKey.accountService.privateKey
		case .pin: return StoreKey.accountService.pin
		case .useBiometry: return StoreKey.accountService.useBiometry
		case .passphrase: return StoreKey.accountService.passphrase
            
        case .mainAccount: return StoreKey.accountService.mainAccount
        case .lastUsedAccount: return StoreKey.accountService.lastUsedAccount
        case .additionalAccounts: return StoreKey.accountService.additionalAccounts
            
        case .addressPool: return StoreKey.accountService.addressPool
		}
	}
}

fileprivate extension SecuredStore {
	func set(_ value: String, for key: Key) {
		set(value, for: key.stringValue)
	}
	
	func get(_ key: Key) -> String? {
		return get(key.stringValue)
	}
	
	func remove(_ key: Key) {
		remove(key.stringValue)
	}
}

public struct LocalAdamantAccount: Codable, Equatable {
    var name: String
    var address: String
    var passphrase: String
    var publicKey: String?
    var privateKey: String?
    
    var chatProvider: NonificationProviderStorage = NonificationProviderStorage()
    var transfersProvider: NonificationProviderStorage = NonificationProviderStorage()
    
    init(name: String, address: String, passphrase: String = "", keyPair: Keypair? = nil) {
        self.name = name
        self.address = address
        self.passphrase = passphrase
        
        if let keyPair = keyPair {
            self.publicKey = keyPair.publicKey
            self.privateKey = keyPair.privateKey
        }
    }
    
    func getNameOrAddress() -> String {
        if name == "" {
            return address
        }
        return name
    }
    
    func getKeyPair() -> Keypair? {
        if let publicKey = self.publicKey, let privateKey = self.privateKey {
            return Keypair(publicKey: publicKey, privateKey: privateKey)
        }
        return nil
    }
    
    func getUnreaded() -> Int {
        var unreaded = 0
        
        unreaded += chatProvider.notifiedCount ?? 0
        unreaded += transfersProvider.notifiedCount ?? 0
        
        return unreaded
    }
}

public struct NonificationProviderStorage: Codable, Equatable {
    var receivedLastHeight: Int64? = 0
    var readedLastHeight: Int64? = 0
    var notifiedLastHeight: Int64? = 0
    var notifiedCount: Int? = 0
}

extension NonificationProviderStorage {
    func isInitialySynced() -> Bool {
        if let lastHeight = receivedLastHeight, lastHeight > 0 {
            return true
        }
        return false
    }
}

// MARK: - Multi-Account heplers
extension SecuredStore {
    func setLastUsedAccount(_ account: LocalAdamantAccount) {
        set(account.address, for: .lastUsedAccount)
    }
    
    func getMainAccount() -> LocalAdamantAccount? {
        if let mainAccountRaw = self.get(Key.mainAccount), let data = mainAccountRaw.data(using: .utf8) {
            do {
                let mainAccount = try JSONDecoder().decode(LocalAdamantAccount.self, from: data)
                return mainAccount
            } catch let err {
                print("Fail to get main accounts from secure storege with error: ", err)
            }
        }
        
        return nil
    }
    
    func saveMainAccount(_ account: LocalAdamantAccount) -> Bool {
        do {
            let jsonData = try JSONEncoder().encode(account)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                self.set(jsonString, for: .mainAccount)
                return true
            } else {
                print("Fail save main account to secure storege")
                return false
            }
        } catch let err {
            print("Fail save main account to secure storege with error: ", err)
            return false
        }
    }
    
    func getAdditionalAccounts() -> [String : LocalAdamantAccount] {
        if let additionalAccountsRaw = self.get(Key.additionalAccounts), let data = additionalAccountsRaw.data(using: .utf8) {
            
            do {
                let additionalAccounts = try JSONDecoder().decode([String: LocalAdamantAccount].self, from: data)
                return additionalAccounts
            } catch let err {
                print("Fail to get additionl accounts from secure storege with error: ", err)
                return [String : LocalAdamantAccount]()
            }
        } else {
            return [String : LocalAdamantAccount]()
        }
    }
    
    func saveAdditionalAccounts(_ accounts: [String : LocalAdamantAccount]) -> Bool {
        do {
            let jsonData = try JSONEncoder().encode(accounts)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                self.set(jsonString, for: .additionalAccounts)
                return true
            } else {
                print("Fail save additionl accounts to secure storege")
                return false
            }
        } catch let err {
            print("Fail save additionl accounts to secure storege with error: ", err)
            return false
        }
    }
    
    func getAccounts() -> [String : LocalAdamantAccount] {
        var accounts = [String : LocalAdamantAccount]()
        
        if let main = getMainAccount() {
            accounts[main.address] = main
        }
        let additionalAccounts = getAdditionalAccounts()
        accounts.merge(additionalAccounts) { (curent, new) -> LocalAdamantAccount in curent }
        
        return accounts
    }
    
    func getAccount(by address: String) -> LocalAdamantAccount? {
        let accounts = getAccounts()
        return accounts[address]
    }
    
    func updateAccount(_ account: LocalAdamantAccount) {
        let mainAccount = getMainAccount()
        if account.address == mainAccount?.address {
            _ = self.saveMainAccount(account)
        } else {
            var accounts = getAdditionalAccounts()
            accounts[account.address] = account
            _ = self.saveAdditionalAccounts(accounts)
        }
    }
    
    func getAllUnreaded() -> Int {
        var unReaded = 0
        for account in getAccounts().values {
            unReaded += account.getUnreaded()
        }
        return unReaded
    }
    
    // MARK: Address pool methods
    
    func getNextAddress() -> String? {
        let addressPool = getCurrentAddressPool()
        if addressPool.count > 0 {
            return addressPool.first
        } else {
            return getNewAddressPool().first
        }
    }
    
    func getCurrentAddressPool() -> [String] {
        let defaultAddressPool = getAddressPool()
        if var addressPool = getLastAddressPool() {
            if addressPool.count < defaultAddressPool.count {
                addressPool.append(contentsOf: defaultAddressPool)
                saveAddressPool(addressPool)
                return addressPool
            } else {
                return addressPool
            }
        } else {
            saveAddressPool(defaultAddressPool)
            return defaultAddressPool
        }
    }
    
    func removeAddress(_ address: String) {
        if var addressPool = getLastAddressPool() {
            if let idx = addressPool.index(of: address) {
                addressPool.remove(at: idx)
            }
            
            saveAddressPool(addressPool)
        }
    }
    
    private func getAddressPool() -> [String] {
        return Array(getAccounts().keys)
    }
    
    private func getNewAddressPool() -> [String] {
        let addressPool = getAddressPool()
        
        saveAddressPool(addressPool)
        
        return addressPool
    }
    
    private func getLastAddressPool() -> [String]? {
        if let raw = self.get(Key.addressPool), let data = raw.data(using: .utf8) {
            do {
                let addressPool = try JSONDecoder().decode([String].self, from: data)
                
                return addressPool
            } catch let err {
                print("Fail to get address pool from secure storege with error: ", err)
                return nil
            }
        } else {
            return nil
        }
    }
    
    private func saveAddressPool(_ addressPool: [String]) {
        do {
            let jsonData = try JSONEncoder().encode(addressPool)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                self.set(jsonString, for: .addressPool)
            } else {
                print("Fail save address pool to secure storege")
            }
        } catch let err {
            print("Fail save address pool to secure storege with error: ", err)
        }
    }
}
