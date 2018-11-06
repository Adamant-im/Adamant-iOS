//
//  AdamantTransfersProvider.swift
//  Adamant
//
//  Created by Anokhov Pavel on 30.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation
import CoreData

class AdamantTransfersProvider: TransfersProvider {
	// MARK: Dependencies
	var apiService: ApiService!
	var stack: CoreDataStack!
	var accountService: AccountService!
	var accountsProvider: AccountsProvider!
	var securedStore: SecuredStore!
	
	// MARK: Properties
	var transferFee: Decimal = Decimal(sign: .plus, exponent: -1, significand: 5)
	
	private(set) var state: State = .empty
	private(set) var isInitiallySynced: Bool = false
	private(set) var receivedLastHeight: Int64?
	private(set) var readedLastHeight: Int64?
    private let apiTransactions = 100
	
	private let processingQueue = DispatchQueue(label: "im.adamant.processing.transfers", qos: .utility, attributes: [.concurrent])
    private let sendingQueue = DispatchQueue(label: "im.adamant.sending.transfers", qos: .utility, attributes: [.concurrent])
	private let stateSemaphore = DispatchSemaphore(value: 1)
	
    private var unconfirmedTransactions: [UInt64:NSManagedObjectID] = [:]
    private let unconfirmedsSemaphore = DispatchSemaphore(value: 1)
    
	// MARK: Tools
	
	/// Free stateSemaphore before calling this method, or you will deadlock.
	private func setState(_ state: State, previous prevState: State, notify: Bool = true) {
		stateSemaphore.wait()
		self.state = state
		stateSemaphore.signal()
		
		if notify {
			switch prevState {
			case .failedToUpdate(_):
				NotificationCenter.default.post(name: Notification.Name.AdamantTransfersProvider.stateChanged, object: nil, userInfo: [AdamantUserInfoKey.TransfersProvider.newState: state,
																													 AdamantUserInfoKey.TransfersProvider.prevState: prevState])
				
			default:
				if prevState != self.state {
					NotificationCenter.default.post(name: Notification.Name.AdamantTransfersProvider.stateChanged, object: nil, userInfo: [AdamantUserInfoKey.TransfersProvider.newState: state,
																														 AdamantUserInfoKey.TransfersProvider.prevState: prevState])
				}
			}
		}
	}
	
	
	// MARK: Lifecycle
	init() {
		NotificationCenter.default.addObserver(forName: Notification.Name.AdamantAccountService.userLoggedIn, object: nil, queue: nil) { [weak self] notification in
			guard let store = self?.securedStore else {
				return
			}
			
			guard let loggedAddress = notification.userInfo?[AdamantUserInfoKey.AccountService.loggedAccountAddress] as? String else {
				store.remove(StoreKey.transfersProvider.address)
				store.remove(StoreKey.transfersProvider.receivedLastHeight)
				store.remove(StoreKey.transfersProvider.readedLastHeight)
				self?.dropStateData()
				return
			}
			
			if let savedAddress = store.get(StoreKey.transfersProvider.address), savedAddress == loggedAddress {
				if let raw = store.get(StoreKey.transfersProvider.readedLastHeight), let h = Int64(raw) {
					self?.readedLastHeight = h
				}
			} else {
				store.remove(StoreKey.transfersProvider.receivedLastHeight)
				store.remove(StoreKey.transfersProvider.readedLastHeight)
				self?.dropStateData()
				store.set(loggedAddress, for: StoreKey.transfersProvider.address)
			}
			
			self?.update()
		}
		
		NotificationCenter.default.addObserver(forName: Notification.Name.AdamantAccountService.userLoggedOut, object: nil, queue: nil) { [weak self] _ in
			// Drop everything
			self?.reset()
			
			// BackgroundFetch
			self?.dropStateData()
		}
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}


// MARK: - DataProvider
extension AdamantTransfersProvider {
	func reload() {
		reset(notify: false)
		
		update()
	}
	
	func update() {
		self.update(completion: nil)
	}
    
    func update(completion: ((TransfersProviderResult?) -> Void)?) {
        stateSemaphore.wait()
        if state == .updating {
            stateSemaphore.signal()
            completion?(nil)
            return
        }
        
        let prevState = state
        state = .updating
        stateSemaphore.signal()
        
        guard let address = accountService.account?.address else {
            self.setState(.failedToUpdate(TransfersProviderError.notLogged), previous: prevState)
            completion?(.failure(TransfersProviderError.notLogged))
            return
        }
        
        // MARK: 3. Get transactions
        let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        privateContext.parent = stack.container.viewContext
        let processingGroup = DispatchGroup()
        let cms = DispatchSemaphore(value: 1)
        let prevHeight = receivedLastHeight
        
        getTransactions(forAccount: address, type: .send, fromHeight: prevHeight, offset: nil, dispatchGroup: processingGroup, context: privateContext, contextMutatingSemaphore: cms)
        
        // MARK: 4. Check
        processingGroup.notify(queue: DispatchQueue.global(qos: .utility)) { [weak self] in
            guard let state = self?.state else {
                completion?(nil)
                return
            }
            
            switch state {
			case .empty, .updating, .upToDate:
                self?.setState(.upToDate, previous: prevState)
                
                if prevHeight != self?.receivedLastHeight, let h = self?.receivedLastHeight {
                    NotificationCenter.default.post(name: Notification.Name.AdamantChatsProvider.newUnreadMessages,
                                                    object: self,
                                                    userInfo: [AdamantUserInfoKey.TransfersProvider.lastTransactionHeight:h])
                }
                
                if let h = self?.receivedLastHeight {
                    self?.readedLastHeight = h
                } else {
                    self?.readedLastHeight = 0
                }
                
                if var account = self?.securedStore.getAccount(by: address) {
                    if let h = self?.receivedLastHeight {
                       account.transfersProvider.receivedLastHeight = h
                    }
                    
                    if let h = self?.readedLastHeight, h > 0 {
                        account.transfersProvider.readedLastHeight = h
                    }
                    self?.securedStore.updateAccount(account)
                }
                
                if let synced = self?.isInitiallySynced, !synced {
                    self?.isInitiallySynced = true
                    NotificationCenter.default.post(name: Notification.Name.AdamantTransfersProvider.initialSyncFinished, object: self)
                }
                
                completion?(.success)
				
				
			case .failedToUpdate(let error): // Processing failed
				let err: TransfersProviderError
				
				switch error {
				case let error as ApiServiceError:
					switch error {
					case .notLogged:
						err = .notLogged
						
					case .accountNotFound:
						err = .accountNotFound(address: address)
						
					case .serverError(_):
						err = .serverError(error)
						
					case .internalError(let message, _):
						err = .dependencyError(message: message)
						
					case .networkError(_):
						err = .networkError
					}
					
				default:
					err = TransfersProviderError.internalError(message: String.adamantLocalized.sharedErrors.internalError(message: error.localizedDescription), error: error)
				}
				
				completion?(.failure(err))
            }
        }
    }
	
	func reset() {
		reset(notify: true)
	}
	
	private func reset(notify: Bool) {
		isInitiallySynced = false
		let prevState = self.state
		setState(.updating, previous: prevState, notify: false)	// Block update calls
		
		// Drop props
		receivedLastHeight = nil
		readedLastHeight = nil
		
		// Drop store
		securedStore.remove(StoreKey.transfersProvider.address)
		securedStore.remove(StoreKey.transfersProvider.receivedLastHeight)
		securedStore.remove(StoreKey.transfersProvider.readedLastHeight)
		
		// Drop CoreData
		let request = NSFetchRequest<TransferTransaction>(entityName: TransferTransaction.entityName)
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		context.parent = stack.container.viewContext
		
		if let result = try? context.fetch(request) {
			for obj in result {
				context.delete(obj)
			}
			
			try? context.save()
		}
		
		// Set state
		setState(.empty, previous: prevState, notify: notify)
	}
}


// MARK: - TransfersProvider
extension AdamantTransfersProvider {
	// MARK: Controllers
	func transfersController() -> NSFetchedResultsController<TransferTransaction> {
		let request = NSFetchRequest<TransferTransaction>(entityName: TransferTransaction.entityName)
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false),
								   NSSortDescriptor(key: "transactionId", ascending: false)]
		let controller = NSFetchedResultsController(fetchRequest: request, managedObjectContext: stack.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
		
		return controller
	}
	
	func transfersController(for account: CoreDataAccount) -> NSFetchedResultsController<TransferTransaction> {
		let request = NSFetchRequest<TransferTransaction>(entityName: TransferTransaction.entityName)
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false),
								   NSSortDescriptor(key: "transactionId", ascending: false)]
		request.predicate = NSPredicate(format: "partner = %@", account)
		
		let controller = NSFetchedResultsController(fetchRequest: request, managedObjectContext: stack.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
		try! controller.performFetch()
		return controller
	}
	
	func unreadTransfersController() -> NSFetchedResultsController<TransferTransaction> {
		let request = NSFetchRequest<TransferTransaction>(entityName: TransferTransaction.entityName)
		request.predicate = NSPredicate(format: "isUnread == true")
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false),
								   NSSortDescriptor(key: "transactionId", ascending: false)]
		let controller = NSFetchedResultsController(fetchRequest: request, managedObjectContext: stack.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
		
		return controller
	}
	
	// MARK: Sending Funds
    
    // Wrapper
	func transferFunds(toAddress recipient: String, amount: Decimal, completion: @escaping (TransfersProviderResult) -> Void) {
        // Go background
        sendingQueue.async {
            self.transferFundsInternal(toAddress: recipient, amount: amount, completion: completion)
        }
    }
    
    private func transferFundsInternal(toAddress recipient: String, amount: Decimal, completion: @escaping (TransfersProviderResult) -> Void) {
        // MARK: 0. Prepare
		guard let senderId = accountService.account?.address, let keypair = accountService.keypair else {
			completion(.failure(.notLogged))
			return
		}
        
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = stack.container.viewContext
        
        // MARK: 1. Get recipient
        let accountsGroup = DispatchGroup()
        accountsGroup.enter()
        
        var result: AccountsProviderResult! = nil
        accountsProvider.getAccount(byAddress: recipient) { r in
            result = r
            accountsGroup.leave()
        }
        
        accountsGroup.wait()
        
        let recipientAccount: CoreDataAccount
        switch result! {
        case .success(let account):
            recipientAccount = account
            
        case .notFound, .invalidAddress:
            completion(.failure(.accountNotFound(address: recipient)))
            return
            
        case .serverError(let error):
            completion(.failure(.serverError(error)))
            return
            
        case .networkError(_):
            completion(.failure(.networkError))
            return
        }
        
        // MARK: 2. Create transaction
        let transaction = TransferTransaction(context: context)
        transaction.amount = amount as NSDecimalNumber
        transaction.date = Date() as NSDate
        transaction.recipientId = recipient
        transaction.senderId = senderId
        transaction.type = Int16(TransactionType.send.rawValue)
        transaction.isOutgoing = true
        
        transaction.transactionId = UUID().uuidString
        transaction.blockId = UUID().uuidString
        transaction.statusEnum = MessageStatus.pending
        
        // MARK: 3. Chatroom
        if let id = recipientAccount.chatroom?.objectID, let chatroom = context.object(with: id) as? Chatroom {
            chatroom.addToTransactions(transaction)
            
            if let lastTransaction = chatroom.lastTransaction {
                if let dateA = lastTransaction.date as Date?, let dateB = transaction.date as Date?,
                    dateA.compare(dateB) == ComparisonResult.orderedAscending {
                    chatroom.lastTransaction = transaction
                    chatroom.updatedAt = transaction.date
                }
            } else {
                chatroom.lastTransaction = transaction
                chatroom.updatedAt = transaction.date
            }
        }
        
        // MARK: 4. Save unconfirmed transaction
        do {
            try context.save()
        } catch {
            completion(.failure(.internalError(message: "Failed to save context", error: error)))
            return
        }
        
        // MARK: 5. Send
		apiService.transferFunds(sender: senderId, recipient: recipient, amount: amount, keypair: keypair) { result in
			switch result {
			case .success(let id):
                // Update ID with recieved, add to unconfirmed transactions.
                transaction.transactionId = String(id)
                
                self.unconfirmedsSemaphore.wait()
                DispatchQueue.main.sync {
                    self.unconfirmedTransactions[id] = transaction.objectID
                }
                self.unconfirmedsSemaphore.signal()
                
                
				completion(.success)
				
			case .failure(let error):
				completion(.failure(.serverError(error)))
			}
		}
	}
	
	// MARK: Getting & refreshing transfers
	
	/// Search transaction in local storage
	///
	/// - Parameter id: Transacton ID
	/// - Returns: Transaction, if found
	func getTransfer(id: String) -> TransferTransaction? {
		let request = NSFetchRequest<TransferTransaction>(entityName: TransferTransaction.entityName)
		request.predicate = NSPredicate(format: "transactionId == %@", String(id))
		request.fetchLimit = 1
		
		do {
			let result = try stack.container.viewContext.fetch(request)
			return result.first
		} catch {
			return nil
		}
	}
	
	
	/// Call Server, check if transaction updated
	///
	/// - Parameters:
	///   - id: Transaction ID
	///   - completion: callback
	func refreshTransfer(id: String, completion: @escaping (TransfersProviderResult) -> Void) {
		guard let transfer = getTransfer(id: id) else {
			completion(.failure(.transactionNotFound(id: id)))
			return
		}
		
		guard let intId = UInt64(id) else {
			completion(.failure(.internalError(message: "Can't parse transaction id: \(id)", error: nil)))
			return
		}
		
		apiService.getTransaction(id: intId) { result in
			switch result {
			case .success(let transaction):
				guard transfer.confirmations != transaction.confirmations else {
					completion(.success)
					return
				}
				
				// Update transaction
				
				let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
				context.parent = self.stack.container.viewContext
				
				guard let trsfr = context.object(with: transfer.objectID) as? TransferTransaction else {
					completion(.failure(.internalError(message: "Failed to update transaction: CoreData context changed", error: nil)))
					return
				}
				
				trsfr.confirmations = transaction.confirmations
				
				do {
					try context.save()
					completion(.success)
				} catch {
					completion(.failure(.internalError(message: "Failed saving changes to CoreData: \(error.localizedDescription)", error: error)))
				}
				
			case .failure(let error):
				completion(.failure(.serverError(error)))
			}
		}
	}
}


// MARK: - Data processing
extension AdamantTransfersProvider {
	private enum ProcessingResult {
		case success(new: Int)
		case accountNotFound(address: String)
		case error(Error)
	}
    
    /// Get transactions
    ///
    /// - Parameters:
    ///   - account: for account
    ///   - height: last transaction height.
    ///   - offset: offset, if greater than 100
    /// - Returns: ammount of new transactions was added
    private func getTransactions(forAccount account: String,
                                 type: TransactionType,
                                 fromHeight: Int64?,
                                 offset: Int?,
                                 dispatchGroup: DispatchGroup,
                                 context: NSManagedObjectContext,
                                 contextMutatingSemaphore cms: DispatchSemaphore) {
        // Enter 1
        dispatchGroup.enter()
        
        // MARK: 1. Get new transactions
        apiService.getTransactions(forAccount: account, type: type, fromHeight: fromHeight, offset: offset, limit: self.apiTransactions) { result in
            
            defer {
                // Leave 1
                dispatchGroup.leave()
            }
            
            switch result {
            case .success(let transactions):
                guard transactions.count > 0 else {
                    return
                }
                
                // MARK: 2. Process transactions in background
                // Enter 2
                dispatchGroup.enter()
                self.processingQueue.async {
                    defer {
                        // Leave 2
                        dispatchGroup.leave()
                    }
                    
                    self.processRawTransactions(transactions,
                                                currentAddress: account,
                                                context: context,
                                                contextMutatingSemaphore: cms)
                }
                
                // MARK: 3. Get more transactions
                if transactions.count == self.apiTransactions {
                    let newOffset: Int
                    if let offset = offset {
                        newOffset = offset + self.apiTransactions
                    } else {
                        newOffset = self.apiTransactions
                    }
                    
                    self.getTransactions(forAccount: account, type: type, fromHeight: fromHeight, offset: newOffset, dispatchGroup: dispatchGroup, context: context, contextMutatingSemaphore: cms)
                }
                
            case .failure(let error):
                self.setState(.failedToUpdate(error), previous: .updating)
            }
        }
    }
	
    private func processRawTransactions(_ transactions: [Transaction],
                                        currentAddress address: String,
                                        context: NSManagedObjectContext,
                                        contextMutatingSemaphore cms: DispatchSemaphore) {
        // MARK: 0. Transactions?
        guard transactions.count > 0 else {
            return
        }
        
        // MARK: 1. Collect all partners
        var partnerIds: Set<String> = []
        
        for t in transactions {
            if t.senderId == address {
                partnerIds.insert(t.recipientId)
            } else {
                partnerIds.insert(t.senderId)
            }
        }
        
        // MARK: 2. Let AccountProvider get all partners from server.
        let partnersGroup = DispatchGroup()
        var errors: [ProcessingResult] = []
        for id in partnerIds {
            partnersGroup.enter()
            accountsProvider.getAccount(byAddress: id, completion: { result in
                defer {
                    partnersGroup.leave()
                }
                
                switch result {
                case .success(_):
                    break
                    
                case .notFound, .invalidAddress:
					errors.append(ProcessingResult.accountNotFound(address: id))
					
                case .networkError(let error), .serverError(let error):
                    errors.append(ProcessingResult.error(error))
                }
            })
        }
        
        partnersGroup.wait()
        
        // MARK: 2.5. If we have any errors - drop processing.
        if let error = errors.first {
            print(error)
            return
        }
        
        
        // MARK: 3. Create private context, and process transactions
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = self.stack.container.viewContext
        
        var partners: [String:CoreDataAccount] = [:]
        for id in partnerIds {
            let request = NSFetchRequest<CoreDataAccount>(entityName: CoreDataAccount.entityName)
            request.predicate = NSPredicate(format: "address == %@", id)
            request.fetchLimit = 1
            if let partner = (try? context.fetch(request))?.first {
                partners[id] = partner
            }
        }
        
        var transfers = [TransferTransaction]()
        var height: Int64 = 0
        for t in transactions {
            unconfirmedsSemaphore.wait()
            if let objectId = unconfirmedTransactions[t.id], let transaction = context.object(with: objectId) as? TransferTransaction {
                transaction.isConfirmed = true
                transaction.height = t.height
                transaction.blockId = t.blockId
                transaction.confirmations = t.confirmations
                transaction.statusEnum = .delivered
                
                unconfirmedTransactions.removeValue(forKey: t.id)
                
                let h = Int64(t.height)
                if height < h {
                    height = h
                }
                
                unconfirmedsSemaphore.signal()
                continue
            } else {
                unconfirmedsSemaphore.signal()
            }
            
            let transfer = TransferTransaction(context: context)
            transfer.amount = t.amount as NSDecimalNumber
            transfer.date = t.date as NSDate
            transfer.fee = t.fee as NSDecimalNumber
            transfer.height = Int64(t.height)
            transfer.recipientId = t.recipientId
            transfer.senderId = t.senderId
            transfer.transactionId = String(t.id)
            transfer.type = Int16(t.type.rawValue)
            transfer.blockId = t.blockId
            transfer.confirmations = t.confirmations
            transfer.statusEnum = .delivered
            
            transfer.isOutgoing = t.senderId == address
            let partnerId = transfer.isOutgoing ? t.recipientId : t.senderId
            
            if let partner = partners[partnerId] {
                transfer.partner = partner
                transfer.chatroom = partner.chatroom
            }
            
            if t.height > height {
                height = t.height
            }
            
            transfers.append(transfer)
        }
        
        
        // MARK: 4. Check lastHeight
        // API returns transactions from lastHeight INCLUDING transaction with height == lastHeight, so +1
        if height > 0 {
            let uH = Int64(height + 1)
            
            if let lastHeight = receivedLastHeight {
                if lastHeight < uH {
                    self.receivedLastHeight = uH
                }
            } else {
                self.receivedLastHeight = uH
            }
        }
        
        // MARK: 5. Unread transactions
        if let unreadedHeight = readedLastHeight {
            let unreadTransactions = transfers.filter { $0.height > unreadedHeight }
            let chatrooms = Dictionary.init(grouping: unreadTransactions, by: ({ (t: TransferTransaction) -> Chatroom in t.chatroom!}))
            
            for (chatroom, trs) in chatrooms {
                chatroom.hasUnreadMessages = true
                trs.forEach { $0.isUnread = true }
            }
            
            transfers.filter({$0.height > unreadedHeight}).forEach({$0.isUnread = true})
            
            readedLastHeight = self.receivedLastHeight
        }
        
        if let h = self.receivedLastHeight {
            securedStore.set(String(h), for: StoreKey.transfersProvider.receivedLastHeight)
        }
        
        if let h = self.readedLastHeight {
            securedStore.set(String(h), for: StoreKey.transfersProvider.readedLastHeight)
        }
        
        // MARK: 6. Dump transactions to viewContext
        if context.hasChanges {
            do {
                try context.save()
                
                // MARK: 7. Update lastTransactions
                let viewContextChatrooms = Set<Chatroom>(transfers.compactMap { $0.chatroom }).compactMap { self.stack.container.viewContext.object(with: $0.objectID) as? Chatroom }
                DispatchQueue.main.async {
                    viewContextChatrooms.forEach { $0.updateLastTransaction() }
                }
            } catch {
				print("TransferProvider: Failed to save changes to CoreData: \(error.localizedDescription)")
            }
        }
    }
	
}
