//
//  BtcWalletService.swift
//  Adamant
//
//  Created by Anton Boyarkin on 14/01/2019.
//  Copyright © 2019 Adamant. All rights reserved.
//

import UIKit
import Swinject
import BitcoinKit
import BitcoinKit.Private

class BtcWalletService: WalletService {
    var wallet: WalletAccount? { return btcWallet }
    
    var walletViewController: WalletViewController {
        guard let vc = router.get(scene: AdamantScene.Wallets.Bitcoin.wallet) as? BtcWalletViewController else {
            fatalError("Can't get BtcWalletViewController")
        }
        
        vc.service = self
        return vc
    }
    
    // MARK: RichMessageProvider properties
    static let richMessageType = "btc_transaction"
    let cellIdentifierSent = "btcTransferSent"
    let cellIdentifierReceived = "btcTransferReceived"
    let cellSource: CellSource? = CellSource.nib(nib: UINib(nibName: "TransferCollectionViewCell", bundle: nil))
    
    // MARK: - Dependencies
    var apiService: ApiService!
    var accountService: AccountService!
    var dialogService: DialogService!
    var router: Router!
    
    // MARK: - Constants
    static var currencySymbol = "BTC"
    static var currencyLogo = #imageLiteral(resourceName: "wallet_btc")
    
    static let defaultFee: Int64 = Priority.medium.rawValue
    
    enum Priority: Int64 {
        case high = 24000
        case medium = 12000
        case low = 3000
    }
    
    private (set) var transactionFee: Decimal = Decimal(BtcWalletService.defaultFee) / Decimal(100000000)
    
    static let kvsAddress = "btc:address"
    static let kvsCheckpoint = "btc:checkpoint"
    private let walletPath = "m/44'/0'/21'/0/0"
    
    // MARK: - Notifications
    let walletUpdatedNotification = Notification.Name("adamant.brchWallet.walletUpdated")
    let serviceEnabledChanged = Notification.Name("adamant.btcWallet.enabledChanged")
    let serviceStateChanged = Notification.Name("adamant.btcWallet.stateChanged")
    let transactionFeeUpdated = Notification.Name("adamant.btcWallet.feeUpdated")
    
    // MARK: - Delayed KVS save
    private var balanceObserver: NSObjectProtocol? = nil
    
    // MARK: - Properties
    private (set) var btcWallet: BtcWallet? = nil
    
    private (set) var enabled = true
    
    public var network: CustomNetwork
    
    private var checkpointSyncer: CheckpointSyncer?
    
    private var initialBalanceCheck = false
    
    let defaultDispatchQueue = DispatchQueue(label: "im.adamant.btcWalletService", qos: .utility, attributes: [.concurrent])
    let stateSemaphore = DispatchSemaphore(value: 1)
    
    var peerGroup: PeerGroup?
    var blockStore: SQLiteBlockStore?
    
    // MARK: - State
    private (set) var state: WalletServiceState = .notInitiated
    
    private func setState(_ newState: WalletServiceState, silent: Bool = false) {
        guard newState != state else {
            return
        }
        
        state = newState
        
        if !silent {
            NotificationCenter.default.post(name: serviceStateChanged,
                                            object: self,
                                            userInfo: [AdamantUserInfoKey.WalletService.walletState: state])
        }
    }
    
    init(mainnet: Bool) {
        self.network = mainnet ? AdmBTCMainnet() : AdmBTCTestnet()
        
        self.setState(.notInitiated)
        
        self.checkpointSyncer = CheckpointSyncer(network: self.network)
        self.checkpointSyncer?.start()
    }
    
    deinit {
        self.stopSync()
    }
    
    func update() {
        guard let wallet = btcWallet else {
            return
        }
        
        defer { stateSemaphore.signal() }
        stateSemaphore.wait()
        
        switch state {
        case .notInitiated, .updating, .initiationFailed(_):
            return
            
        case .upToDate:
            break
        }
        
        setState(.updating)
        
        getBalance { [weak self] result in
            if let stateSemaphore = self?.stateSemaphore {
                defer {
                    stateSemaphore.signal()
                }
                stateSemaphore.wait()
            }
            
            switch result {
            case .success(let balance):
                let notification: Notification.Name?
                
                if wallet.balance != balance {
                    wallet.balance = balance
                    notification = self?.walletUpdatedNotification
                    self?.initialBalanceCheck = false
                } else if let initialBalanceCheck = self?.initialBalanceCheck, initialBalanceCheck {
                    self?.initialBalanceCheck = false
                    notification = self?.walletUpdatedNotification
                } else {
                    notification = nil
                }
                
                if let notification = notification {
                    NotificationCenter.default.post(name: notification, object: self, userInfo: [AdamantUserInfoKey.WalletService.wallet: wallet])
                }
                
            case .failure(let error):
                self?.dialogService.showRichError(error: error)
            }
            
            self?.setState(.upToDate)
            self?.stateSemaphore.signal()
        }
    }
    
    func validate(address: String) -> AddressValidationResult {
        return isValid(bitcoinAddress: address) ? .valid : .invalid
    }

    private func getBase58DecodeAsBytes(address: String, length: Int) -> [UTF8.CodeUnit]? {
        let b58Chars = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

        var output: [UTF8.CodeUnit] = Array(repeating: 0, count: length)

        for i in 0..<address.count {
            let index = address.index(address.startIndex, offsetBy: i)
            let charAtIndex = address[index]

            guard let charLoc = b58Chars.index(of: charAtIndex) else { continue }

            var p = b58Chars.distance(from: b58Chars.startIndex, to: charLoc)
            for j in stride(from: length - 1, through: 0, by: -1) {
                p += 58 * Int(output[j] & 0xFF)
                output[j] = UTF8.CodeUnit(p % 256)

                p /= 256
            }

            guard p == 0 else { return nil }
        }

        return output
    }

    public func isValid(bitcoinAddress address: String) -> Bool {
        guard address.count >= 26 && address.count <= 35,
            address.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil,
            let decodedAddress = getBase58DecodeAsBytes(address: address, length: 25),
            decodedAddress.count >= 4
            else { return false }

        let decodedAddressNoCheckSum = Array(decodedAddress.prefix(decodedAddress.count - 4))
        let hashedSum = decodedAddressNoCheckSum.sha256().sha256()

        let checkSum = Array(decodedAddress.suffix(from: decodedAddress.count - 4))
        let hashedSumHeader = Array(hashedSum.prefix(4))

        return hashedSumHeader == checkSum
    }
    
    func getWalletAddress(byAdamantAddress address: String, completion: @escaping (WalletServiceResult<String>) -> Void) {
        apiService.get(key: BtcWalletService.kvsAddress, sender: address) { (result) in
            switch result {
            case .success(let value):
                if let address = value {
                    completion(.success(result: address))
                } else {
                    completion(.failure(error: .walletNotInitiated))
                }
                
            case .failure(let error):
                completion(.failure(error: .internalError(message: "BTC Wallet: fail to get address from KVS", error: error)))
            }
        }
    }
    
    func getCheckpoint(byAdamantAddress address: String, completion: @escaping (WalletServiceResult<Checkpoint>) -> Void) {
        apiService.get(key: BtcWalletService.kvsCheckpoint, sender: address) { (result) in
            switch result {
            case .success(let rawValue):
                guard let value = rawValue else {
                    completion(.failure(error: .walletNotInitiated))
                    return
                }
                
                guard let object = value.toDictionary(), let checkpoint = Checkpoint.fromDictionry(object) else {
                    completion(.failure(error: .internalError(message: "Processing error", error: nil)))
                    return
                }
                
                completion(.success(result: checkpoint))
                
            case .failure(let error):
                completion(.failure(error: .internalError(message: "BTC Wallet: fail to get Checpoint from KVS", error: error)))
            }
        }
    }
    
    func startSync(from checkpoint: Checkpoint) {
        print("start sync")
        
        self.network.customCheckpoint = checkpoint
        
        var bdName: String? = nil
        var dbPassphrase: String? = nil
        if let privateKey = btcWallet?.privateKey.data.bytes {
            bdName = "\(privateKey.hexString())-\(self.network.scheme)-\(self.network.alias)".sha256().sha512().md5()
            dbPassphrase = privateKey.hexString()
        }
        
        let blockStore = SQLiteBlockStore(network: self.network, name: bdName, passphrase: dbPassphrase, isCompact: true)
        let blockChain = BlockChain(network: self.network, blockStore: blockStore)
        self.peerGroup = PeerGroup(blockChain: blockChain)
        self.peerGroup?.delegate = self
        
        self.blockStore = blockStore
        
        if let wallet = self.btcWallet {
            let address = wallet.publicKey.toCashaddr()
            self.peerGroup?.addAddressFilter([address])
        }
        
        self.peerGroup?.start()
        
        self.initialBalanceCheck = true
//        self.setState(.upToDate, silent: true)
//        self.update()
    }
    
    func stopSync() {
        if let peerGroup = peerGroup {
            print("stop sync")
            peerGroup.stop()
        }
    }
}
                        
// MARK: - WalletInitiatedWithPassphrase
extension BtcWalletService: InitiatedWithPassphraseService {
    func setInitiationFailed(reason: String) {
        stateSemaphore.wait()
        setState(.initiationFailed(reason: reason))
        btcWallet = nil
        stateSemaphore.signal()
    }
    
    func initWallet(withPassphrase passphrase: String, completion: @escaping (WalletServiceResult<WalletAccount>) -> Void) {
        guard let adamant = accountService.account else {
            completion(.failure(error: .notLogged))
            return
        }
        
        stateSemaphore.wait()
        
        setState(.notInitiated)
        
        if enabled {
            enabled = false
            NotificationCenter.default.post(name: serviceEnabledChanged, object: self)
        }
        
        defaultDispatchQueue.async { [unowned self] in
            let mnemonic = passphrase.components(separatedBy: " ")
            let seed = BitcoinKit.Mnemonic.seed(mnemonic: mnemonic)
            
            let keychain = HDKeychain(seed: seed, network: self.network)
            guard let privateKey = try? keychain.derivedKey(path: self.walletPath).privateKey() else {
                completion(.failure(error: .accountNotFound))
                self.stateSemaphore.signal()
                return
            }
            
            let eWallet = BtcWallet(privateKey: privateKey)
            self.btcWallet = eWallet
            
            if !self.enabled {
                self.enabled = true
                NotificationCenter.default.post(name: self.serviceEnabledChanged, object: self)
            }
            
            self.stateSemaphore.signal()
            
            // MARK: 4. Save address into KVS
            self.getWalletAddress(byAdamantAddress: adamant.address) { [weak self] result in
                guard let service = self else {
                    return
                }
                
                switch result {
                case .success(let address):
                    // BTC already saved
                    if address != eWallet.address {
                        service.save(btcAddress: eWallet.address) { result in
                            service.kvsSaveCompletionRecursion(btcAddress: eWallet.address, result: result)
                        }
                        
                        service.checkpointSyncer?.onFinish { checkpoint in
                            service.save(btcCheckpoint: checkpoint) { result in
                                service.kvsSaveCompletionRecursion(btcCheckpoint: checkpoint, result: result)
                            }

                            service.startSync(from: checkpoint)
                            completion(.success(result: eWallet))
                        }
                        return
                    }

                    // MARK: 5. Save checkpoint into KVS
                    service.initChecpoint(for: adamant.address) { result in
                        switch result {
                        case .success(let checkpoint):
                            service.startSync(from: checkpoint)
                            completion(.success(result: eWallet))
                        case .failure(let error):
                            completion(.failure(error: error))
                            return
                        }
                    }

                    completion(.success(result: eWallet))
                    
                case .failure(let error):
                    switch error {
                    case .walletNotInitiated:
                        // Show '0' without waiting for balance update
                        if let wallet = service.btcWallet {
                            NotificationCenter.default.post(name: service.walletUpdatedNotification, object: service, userInfo: [AdamantUserInfoKey.WalletService.wallet: wallet])
                        }

                        service.save(btcAddress: eWallet.address) { result in
                            service.kvsSaveCompletionRecursion(btcAddress: eWallet.address, result: result)
                        }
                        service.setState(.upToDate)
                        completion(.success(result: eWallet))

                    default:
                        service.setState(.upToDate)
                        completion(.failure(error: error))
                    }
                }
            }
        }
    }
    
    func initChecpoint(for address: String, completion: @escaping (WalletServiceResult<Checkpoint>) -> Void) {
        self.getCheckpoint(byAdamantAddress: address) { [weak self]  result in
            guard let service = self else {
                return
            }
            
            switch result {
            case .success(let value):
                service.checkpointSyncer?.stop()
                completion(.success(result: value))
                
            case .failure(let error):
                switch error {
                case .walletNotInitiated:
                    service.checkpointSyncer?.onFinish { checkpoint in
                        service.save(btcCheckpoint: checkpoint) { result in
                            service.kvsSaveCompletionRecursion(btcCheckpoint: checkpoint, result: result)
                        }
                        
                        completion(.success(result: checkpoint))
                    }
                    
                default:
                    completion(.failure(error: error))
                }
            }
        }
    }
}

// MARK: - Dependencies
extension BtcWalletService: SwinjectDependentService {
    func injectDependencies(from container: Container) {
        accountService = container.resolve(AccountService.self)
        apiService = container.resolve(ApiService.self)
        dialogService = container.resolve(DialogService.self)
        router = container.resolve(Router.self)
    }
}

// MARK: - Balances & addresses
extension BtcWalletService {
    func getBalance(_ completion: @escaping (WalletServiceResult<Decimal>) -> Void) {
        if let address = self.btcWallet?.publicKey.toCashaddr(), let blockChain = self.peerGroup?.blockChain {
            defaultDispatchQueue.async {
                let balance: Int64 = try! blockChain.calculateBalance(address: address)
                
                DispatchQueue.main.async {
                    let decimal = Decimal(balance)
                    completion(.success(result: (decimal / Decimal(100000000))))
                }
            }
        } else {
            completion(.failure(error: .internalError(message: "BTC Wallet: not found", error: nil)))
        }
    }
}

// MARK: - KVS
extension BtcWalletService {
    /// - Parameters:
    ///   - btcAddress: Bitcoin address to save into KVS
    ///   - adamantAddress: Owner of BTC address
    ///   - completion: success
    private func save(btcAddress: String, completion: @escaping (WalletServiceSimpleResult) -> Void) {
        guard let adamant = accountService.account, let keypair = accountService.keypair else {
            completion(.failure(error: .notLogged))
            return
        }
        
        guard adamant.balance >= AdamantApiService.KvsFee else {
            completion(.failure(error: .notEnoughMoney))
            return
        }
        
        apiService.store(key: BtcWalletService.kvsAddress, value: btcAddress, type: .keyValue, sender: adamant.address, keypair: keypair) { result in
            switch result {
            case .success:
                completion(.success)
                
            case .failure(let error):
                completion(.failure(error: .apiError(error)))
            }
        }
    }
    
    private func save(btcCheckpoint: Checkpoint, completion: @escaping (WalletServiceSimpleResult) -> Void) {
        guard let adamant = accountService.account, let keypair = accountService.keypair else {
            completion(.failure(error: .notLogged))
            return
        }
        
        guard adamant.balance >= AdamantApiService.KvsFee else {
            completion(.failure(error: .notEnoughMoney))
            return
        }
        
        let value = JSONStringify(value: btcCheckpoint.toDictionry() as AnyObject)
        
        apiService.store(key: BtcWalletService.kvsCheckpoint, value: value, type: .keyValue, sender: adamant.address, keypair: keypair) { result in
            switch result {
            case .success:
                completion(.success)
                
            case .failure(let error):
                completion(.failure(error: .apiError(error)))
            }
        }
    }
    
    /// New accounts doesn't have enought money to save KVS. We need to wait for balance update, and then - retry save
    private func kvsSaveCompletionRecursion(btcAddress: String, result: WalletServiceSimpleResult) {
        if let observer = balanceObserver {
            NotificationCenter.default.removeObserver(observer)
            balanceObserver = nil
        }
        
        switch result {
        case .success:
            break
            
        case .failure(let error):
            switch error {
            case .notEnoughMoney:  // Possibly new account, we need to wait for dropship
                // Register observer
                let observer = NotificationCenter.default.addObserver(forName: NSNotification.Name.AdamantAccountService.accountDataUpdated, object: nil, queue: nil) { [weak self] _ in
                    guard let balance = self?.accountService.account?.balance, balance > AdamantApiService.KvsFee else {
                        return
                    }
                    
                    self?.save(btcAddress: btcAddress) { result in
                        self?.kvsSaveCompletionRecursion(btcAddress: btcAddress, result: result)
                    }
                }
                
                // Save referense to unregister it later
                balanceObserver = observer
                
            default:
                dialogService.showRichError(error: error)
            }
        }
    }
    
    
    private func kvsSaveCompletionRecursion(btcCheckpoint: Checkpoint, result: WalletServiceSimpleResult) {
        if let observer = balanceObserver {
            NotificationCenter.default.removeObserver(observer)
            balanceObserver = nil
        }
        
        switch result {
        case .success:
            break
            
        case .failure(let error):
            switch error {
            case .notEnoughMoney:  // Possibly new account, we need to wait for dropship
                // Register observer
                let observer = NotificationCenter.default.addObserver(forName: NSNotification.Name.AdamantAccountService.accountDataUpdated, object: nil, queue: nil) { [weak self] _ in
                    guard let balance = self?.accountService.account?.balance, balance > AdamantApiService.KvsFee else {
                        return
                    }
                    
                    self?.save(btcCheckpoint: btcCheckpoint) { result in
                        self?.kvsSaveCompletionRecursion(btcCheckpoint: btcCheckpoint, result: result)
                    }
                }
                
                // Save referense to unregister it later
                balanceObserver = observer
                
            default:
                dialogService.showRichError(error: error)
            }
        }
    }
}

// MARK: - Transactions
extension BtcWalletService {
    func getTransactions(_ completion: @escaping (ApiServiceResult<[Payment]>) -> Void) {
        if let address = self.btcWallet?.publicKey.toCashaddr(), let blockStore = self.blockStore {
            defaultDispatchQueue.async {
                if let transactions = try? blockStore.transactions(address: address) {
                     completion(.success(transactions))
                } else {
                    completion(.success([Payment]()))
                }
            }
        } else {
            completion(.failure(.internalError(message: "BTC Wallet: not found", error: nil)))
        }
    }
    
    func getTransaction(by hash: String, completion: @escaping (ApiServiceResult<Payment>) -> Void) {
        defaultDispatchQueue.async {
            do {
                if let transaction = try self.blockStore?.transaction(with: hash) {
                    completion(.success(transaction))
                } else {
                    completion(.failure(.internalError(message: "No transaction", error: nil)))
                }
            } catch (let error) {
                completion(ApiServiceResult.failure(ApiServiceError.networkError(error: AdamantError(message: "Problem with getting BTC transaction", error: error))))
            }
        }
    }
}

extension BtcWalletService: WalletServiceWithTransfers {
    func transferListViewController() -> UIViewController {
        guard let vc = router.get(scene: AdamantScene.Wallets.Bitcoin.transactionsList) as? BtcTransactionsViewController else {
            fatalError("Can't get BtcTransactionsViewController")
        }
        
        vc.btcWalletService = self
        return vc
    }
}


// BTC Sync
extension BtcWalletService: PeerGroupDelegate {
    func peerGroupDidStop(_ peerGroup: PeerGroup) {
        peerGroup.delegate = nil
        self.peerGroup = nil
    }
    
    func peerGroupDidChanged(_ state: PeerState) {
        switch state {
        case .notSynced:
            self.setState(.notInitiated, silent: false)
        case .syncing(_):
            self.setState(.updating, silent: false)
        case .synced:
            self.initialBalanceCheck = false
            self.setState(.upToDate, silent: false)
            self.update()
        }
    }
}

class CustomNetwork: Network {
    public var customCheckpoint: Checkpoint?
}

class AdmBTCTestnet: CustomNetwork {
    
    public override var name: String {
        return "testnet"
    }
    public override var alias: String {
        return "testnet"
    }
    override public var pubkeyhash: UInt8 {
        return 0x6f
    }
    override public var privatekey: UInt8 {
        return 0xef
    }
    override public var scripthash: UInt8 {
        return 0xc4
    }
    override public var xpubkey: UInt32 {
        return 0x043587cf
    }
    override public var xprivkey: UInt32 {
        return 0x04358394
    }
    public override var port: UInt32 {
        return 18_333
    }
    override public var checkpoints: [Checkpoint] {
        var value = [
            Checkpoint(height: 0, hash: genesisBlock, timestamp: 1_376_543_922, target: 0x1d00ffff),
            Checkpoint(height: 1450248, hash: Data(Data(hex: "000000000000d19bf1c7fdcc2f2d9a917fd837628ce09ed9439771a6d8391210")!.reversed()), timestamp: 1546234270, target: 0x1d00ffff)
        ]
        
        if let checkpoint = customCheckpoint {
            value.append(checkpoint)
        }
        return value
    }
    override public var genesisBlock: Data {
        return Data(Data(hex: "000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943")!.reversed())
    }
    
    override var scheme: String {
        return "bitcoin"
    }

    override public var magic: UInt32 {
        return 0x0b110907
    }
    override var dnsSeeds: [String] {
        return [
//            "testnet-seed.bitcoin.jonasschnelli.ch", // Jonas Schnelli
            "testnet-seed.bluematt.me",              // Matt Corallo
            "testnet-seed.bitcoin.petertodd.org",    // Peter Todd
            "testnet-seed.bitcoin.schildbach.de",    // Andreas Schildbach
            "bitcoin-testnet.bloqseeds.net"         // Bloq
        ]
    }
}

class AdmBTCMainnet: CustomNetwork {
    
    public override var name: String {
        return "livenet"
    }
    public override var alias: String {
        return "mainnet"
    }
    override public var pubkeyhash: UInt8 {
        return 0x00
    }
    override public var privatekey: UInt8 {
        return 0x80
    }
    override public var scripthash: UInt8 {
        return 0x05
    }
    override public var xpubkey: UInt32 {
        return 0x0488b21e
    }
    override public var xprivkey: UInt32 {
        return 0x0488ade4
    }
    public override var port: UInt32 {
        return 8333
    }
    override public var checkpoints: [Checkpoint] {
        var value = [
            Checkpoint(height: 0, hash: genesisBlock, timestamp: 1_231_006_505, target: 0x1d00ffff),
            Checkpoint(height: 564_356, hash: Data(Data(hex: "000000000000000000003d8a4f78cb280e50012872e93c5b5076b4f0419deeb8")!.reversed()), timestamp: 1_550_948_622, target: 0x172e6f88)
        ]
        
        if let checkpoint = customCheckpoint {
            value.append(checkpoint)
        }
        return value
    }
    override public var genesisBlock: Data {
        return Data(Data(hex: "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")!.reversed())
    }
    
    public override var scheme: String {
        return "bitcoin"
    }
    
    override public var magic: UInt32 {
        return 0xf9beb4d9
    }
    
    override var dnsSeeds: [String] {
        return [
            "btcnode1.adamant.im"
        ]
    }
}

extension Checkpoint {
    static func fromDictionry(_ dictionry: [String: Any]) -> Checkpoint? {
        guard let hashString = dictionry["hash"] as? String else {
            return nil
        }
        
        guard let height = dictionry["height"] as? Int32 else {
            return nil
        }
        
        let hash = Data(hex: hashString).map { Data($0.reversed()) } ?? Data()
        
        return Checkpoint(height: height, hash: hash)
    }
    
    func toDictionry() -> [String: Any] {
        return [
            "hash": hash.reversed().hexString(),
            "height": height
        ]
    }
}
