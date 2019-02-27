//
//  AdamantAccountService.swift
//  Adamant
//
//  Created by Anokhov Pavel on 07.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation

class AdamantAccountService: AccountService {
	
	// MARK: Dependencies
	
	var apiService: ApiService!
	var adamantCore: AdamantCore!
	weak var notificationsService: NotificationsService!
    var dialogService: DialogService!
	var securedStore: SecuredStore! {
		didSet {
			securedStoreSemaphore.wait()
			defer {
				securedStoreSemaphore.signal()
			}
			
            if securedStore.get(.passphrase) != nil {
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
		EthWalletService(),
        LskWalletService(mainnet: true, origins: AdamantResources.lskServers),
//        BtcWalletService(mainnet: true)
        
        // Testnet
//        LskWalletService(mainnet: false)
        BtcWalletService(mainnet: false)
	]
    
    init() {
        guard let ethWallet = wallets[1] as? EthWalletService else {
            fatalError("Failed to get EthWalletService")
        }
        
        ethWallet.initiateNetwork(apiUrl: AdamantResources.ethServers.first!) { result in
            switch result {
            case .success:
                break
                
            case .failure(let error):
                switch error {
                case .networkError:
                    NotificationCenter.default.addObserver(forName: Notification.Name.AdamantReachabilityMonitor.reachabilityChanged, object: nil, queue: nil) { notification in
                        guard let connection = notification.userInfo?[AdamantUserInfoKey.ReachabilityMonitor.connection] as? AdamantConnection else {
                            return
                        }
                        
                        switch connection {
                        case .none:
                            break
                            
                        case .wifi, .cellular:
                            ethWallet.initiateNetwork(apiUrl: AdamantResources.ethServers.first!) { result in
                                switch result {
                                case .success:
                                    NotificationCenter.default.removeObserver(self, name: Notification.Name.AdamantReachabilityMonitor.reachabilityChanged, object: nil)
                                    
                                case .failure(let error):
                                    self.dialogService.showRichError(error: error)
                                }
                            }
                        }
                    }
                    
                case .notLogged, .transactionNotFound, .notEnoughMoney, .accountNotFound, .walletNotInitiated, .invalidAmount:
                    break
                    
                case .remoteServiceError, .apiError, .internalError:
                    self.dialogService.showRichError(error: error)
                    self.wallets.remove(at: 1)
                }
            }
        }
    }
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
			securedStore.set(passphrase, for: .passphrase)
		} else {
			securedStore.set(keypair.publicKey, for: .publicKey)
			securedStore.set(keypair.privateKey, for: .privateKey)
		}
		
		hasStayInAccount = true
		NotificationCenter.default.post(name: Notification.Name.AdamantAccountService.stayInChanged, object: self, userInfo: [AdamantUserInfoKey.AccountService.newStayInState : true])
		completion(.success(account: account, alert: nil))
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
        securedStore.remove(.showedV12)
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
		
		guard let loggedAccount = account, let publicKey = loggedAccount.publicKey else {
			return
		}
		
		apiService.getAccount(byPublicKey: publicKey) { [weak self] result in
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
		guard AdamantUtilities.validateAdamantPassphrase(passphrase: passphrase) else {
			completion(.failure(.invalidPassphrase))
			return
		}
		
		guard let keypair = adamantCore.createKeypairFor(passphrase: passphrase) else {
			completion(.failure(.internalError(message: "Failed to generate keypair for passphrase", error: nil)))
			return
		}
		
		loginWith(keypair: keypair) { [weak self] result in
			guard case .success = result else {
				completion(result)
				return
			}
			
			// MARK: Drop saved accs
			if let storedPassphrase = self?.getSavedPassphrase(), storedPassphrase != passphrase {
				self?.dropSavedAccount()
			}
			
			if let storedKeypair = self?.getSavedKeypair(), storedKeypair != self?.keypair {
				self?.dropSavedAccount()
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
			loginWith(passphrase: passphrase, completion: completion)
			return
		}
		
		if let keypair = getSavedKeypair() {
			loginWith(keypair: keypair) { [weak self] result in
				switch result {
				case .success(let account, _):
                    
                    let alert: (title: String, message: String)?
                    if self?.securedStore.get(.showedV12) != nil {
                        alert = nil
                    } else {
                        self?.securedStore.set("1", for: .showedV12)
                        alert = (title: String.adamantLocalized.accountService.updateAlertTitleV12,
                                 message: String.adamantLocalized.accountService.updateAlertMessageV12)
                    }
                    
					completion(.success(account: account, alert: alert))
                    
                    if let wallets = self?.wallets {
                        for case let wallet as InitiatedWithPassphraseService in wallets {
                            wallet.setInitiationFailed(reason: String.adamantLocalized.accountService.reloginToInitiateWallets)
                        }
                    }
					
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
			logout(lockSemaphore: false)
			
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
	
	private func logout(lockSemaphore: Bool) {
		if account != nil {
			NotificationCenter.default.post(name: Notification.Name.AdamantAccountService.userWillLogOut, object: self)
		}
		
		dropSavedAccount()
		
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
			NotificationCenter.default.post(name: Notification.Name.AdamantAccountService.userLoggedOut, object: self)
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
        static let showedV12 = "accountService.showedV12"
		
		private init() {}
	}
}

fileprivate enum Key {
	case publicKey
	case privateKey
	case pin
	case useBiometry
	case passphrase
    case showedV12
	
	var stringValue: String {
		switch self {
		case .publicKey: return StoreKey.accountService.publicKey
		case .privateKey: return StoreKey.accountService.privateKey
		case .pin: return StoreKey.accountService.pin
		case .useBiometry: return StoreKey.accountService.useBiometry
		case .passphrase: return StoreKey.accountService.passphrase
        case .showedV12: return StoreKey.accountService.showedV12
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
