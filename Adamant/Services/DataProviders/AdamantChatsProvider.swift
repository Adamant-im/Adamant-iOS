//
//  AdamantChatsProvider.swift
//  Adamant
//
//  Created by Anokhov Pavel on 05.02.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation
import CoreData

class AdamantChatsProvider: ChatsProvider {
	// MARK: Dependencies
	var accountService: AccountService!
	var apiService: ApiService!
	var stack: CoreDataStack!
	var adamantCore: AdamantCore!
	var accountsProvider: AccountsProvider!
	var securedStore: SecuredStore!
	
    var richProviders: [String:RichMessageProviderWithStatusCheck]!
    
	// MARK: Properties
	private(set) var state: State = .empty
	private(set) var isInitiallySynced: Bool = false
	private(set) var receivedLastHeight: Int64?
	private(set) var readedLastHeight: Int64?
	private let apiTransactions = 100
	private var unconfirmedTransactions: [UInt64:NSManagedObjectID] = [:]
	
	private let processingQueue = DispatchQueue(label: "im.adamant.processing.chat", qos: .utility, attributes: [.concurrent])
	private let sendingQueue = DispatchQueue(label: "im.adamant.sending.chat", qos: .utility, attributes: [.concurrent])
	private let unconfirmedsSemaphore = DispatchSemaphore(value: 1)
	private let highSemaphore = DispatchSemaphore(value: 1)
	private let stateSemaphore = DispatchSemaphore(value: 1)
	
	// MARK: Lifecycle
	init() {
		NotificationCenter.default.addObserver(forName: Notification.Name.AdamantAccountService.userLoggedIn, object: nil, queue: nil) { [weak self] notification in
			guard let store = self?.securedStore else {
				return
			}
			
			guard let loggedAddress = notification.userInfo?[AdamantUserInfoKey.AccountService.loggedAccountAddress] as? String else {
				store.remove(StoreKey.chatProvider.address)
				store.remove(StoreKey.chatProvider.receivedLastHeight)
				store.remove(StoreKey.chatProvider.readedLastHeight)
				self?.dropStateData()
				return
			}
			
            if let account = store.getAccount(by: loggedAddress) {
                if let readedLastHeight = account.chatProvider.readedLastHeight, readedLastHeight > 0 {
                    self?.readedLastHeight = readedLastHeight
                } else {
                    self?.readedLastHeight = nil
                }
            } else {
                self?.dropStateData()
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
	
	// MARK: Tools
	/// Free stateSemaphore before calling this method, or you will deadlock.
	private func setState(_ state: State, previous prevState: State, notify: Bool = true) {
		stateSemaphore.wait()
		self.state = state
		stateSemaphore.signal()
		
		if notify {
			switch prevState {
			case .failedToUpdate(_):
				NotificationCenter.default.post(name: Notification.Name.AdamantTransfersProvider.stateChanged, object: self, userInfo: [AdamantUserInfoKey.TransfersProvider.newState: state,
																													AdamantUserInfoKey.TransfersProvider.prevState: prevState])
				
			default:
				if prevState != self.state {
					NotificationCenter.default.post(name: Notification.Name.AdamantTransfersProvider.stateChanged, object: self, userInfo: [AdamantUserInfoKey.TransfersProvider.newState: state,
																														AdamantUserInfoKey.TransfersProvider.prevState: prevState])
				}
			}
		}
	}
}


// MARK: - DataProvider
extension AdamantChatsProvider {
	func reload() {
		reset(notify: false)
		update()
	}
	
	func reset() {
		reset(notify: true)
	}
	
	private func reset(notify: Bool) {
		isInitiallySynced = false
		let prevState = self.state
		setState(.updating, previous: prevState, notify: false) // Block update calls
		
		// Drop props
		receivedLastHeight = nil
		readedLastHeight = nil
		
		// Drop store
		securedStore.remove(StoreKey.chatProvider.address)
		securedStore.remove(StoreKey.chatProvider.receivedLastHeight)
		securedStore.remove(StoreKey.chatProvider.readedLastHeight)
		
		// Drop CoreData
		let chatrooms = NSFetchRequest<Chatroom>(entityName: Chatroom.entityName)
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		context.parent = stack.container.viewContext
		
		if let results = try? context.fetch(chatrooms) {
			for obj in results {
				context.delete(obj)
			}
			
			try? context.save()
		}
		
		// Set State
		setState(.empty, previous: prevState, notify: notify)
	}
	
	func update() {
		self.update(completion: nil)
	}
    
    func update(completion: ((ChatsProviderResult?) -> Void)?) {
        if state == .updating {
            completion?(nil)
            return
        }
        
        stateSemaphore.wait()
        // MARK: 1. Check state
        if state == .updating {
            stateSemaphore.signal()
            completion?(nil)
            return
        }
        
        // MARK: 2. Prepare
        let prevState = state
        
        guard let address = accountService.account?.address, let privateKey = accountService.keypair?.privateKey else {
            stateSemaphore.signal()
            setState(.failedToUpdate(ChatsProviderError.notLogged), previous: prevState)
            completion?(.failure(ChatsProviderError.notLogged))
            return
        }
        
        state = .updating
        stateSemaphore.signal()
        
        // MARK: 3. Get transactions
        let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        privateContext.parent = self.stack.container.viewContext
        let processingGroup = DispatchGroup()
        let cms = DispatchSemaphore(value: 1)
        let prevHeight = receivedLastHeight
        
        getTransactions(senderId: address, privateKey: privateKey, height: receivedLastHeight, offset: nil, dispatchGroup: processingGroup, context: privateContext, contextMutatingSemaphore: cms)
        
        // MARK: 4. Check
        processingGroup.notify(queue: DispatchQueue.global(qos: .utility)) { [weak self] in
            guard let state = self?.state else {
                completion?(.failure(.dependencyError("Updating")))
                return
            }
            
            switch state {
			case .upToDate, .empty, .updating:
				self?.setState(.upToDate, previous: prevState)
				
				if prevHeight != self?.receivedLastHeight, let h = self?.receivedLastHeight {
					NotificationCenter.default.post(name: Notification.Name.AdamantChatsProvider.newUnreadMessages,
													object: self,
													userInfo: [AdamantUserInfoKey.ChatProvider.lastMessageHeight:h])
				}
				
				if let h = self?.receivedLastHeight {
					self?.readedLastHeight = h
				} else {
					self?.readedLastHeight = 0
				}
				
				if var account = self?.securedStore.getAccount(by: address) {
                    self?.isInitiallySynced = account.chatProvider.isInitialySynced()
                    
					if let h = self?.receivedLastHeight {
                        account.chatProvider.receivedLastHeight = h
					}
					
					if let h = self?.readedLastHeight, h > 0 {
                        account.chatProvider.readedLastHeight = h
					}
                    
                    self?.securedStore.updateAccount(account)
				}
				
				if let synced = self?.isInitiallySynced, !synced {
					self?.isInitiallySynced = true
					NotificationCenter.default.post(name: Notification.Name.AdamantChatsProvider.initialSyncFinished, object: self)
				}
				
				completion?(.success)
				
            case .failedToUpdate(let error): // Processing failed
				let err: ChatsProviderError
				
				switch error {
				case let error as ApiServiceError:
					switch error {
					case .notLogged:
						err = .notLogged
						
					case .accountNotFound:
						err = .accountNotFound(address)
						
					case .serverError(_):
						err = .serverError(error)
						
					case .internalError(let message, _):
						err = .dependencyError(message)
						
					case .networkError(_):
						err = .networkError
					}
					
				default:
					err = .internalError(error)
				}
				
				completion?(.failure(err))
            }
        }
    }
}


// MARK: - Sending messages {
extension AdamantChatsProvider {
	func sendMessage(_ message: AdamantMessage, recipientId: String, completion: @escaping (ChatsProviderResult) -> Void) {
        guard let loggedAccount = accountService.account, let keypair = accountService.keypair else {
            completion(.failure(.notLogged))
            return
        }
        
        guard loggedAccount.balance >= message.fee else {
            completion(.failure(.notEnoughtMoneyToSend))
            return
        }
        
        switch validateMessage(message) {
        case .isValid:
            break
            
        case .empty:
            completion(.failure(.messageNotValid(.empty)))
            return
            
        case .tooLong:
            completion(.failure(.messageNotValid(.tooLong)))
            return
        }
        
        sendingQueue.async {
            switch message {
			case .text(let text), .markdownText(let text):
                self.sendTextMessage(text: text, senderId: loggedAccount.address, recipientId: recipientId, keypair: keypair, type: message.chatType, completion: completion)
				
			case .richMessage(let payload):
                self.sendRichMessage(richContent: payload.content(), richType: payload.type, senderId: loggedAccount.address, recipientId: recipientId, keypair: keypair, completion: completion)
			}
        }
    }
	
    private func sendTextMessage(text: String, senderId: String, recipientId: String, keypair: Keypair, type: ChatType, completion: @escaping (ChatsProviderResult) -> Void) {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = stack.container.viewContext
        
        let transaction = MessageTransaction(context: context)
        transaction.date = Date() as NSDate
        transaction.recipientId = recipientId
        transaction.senderId = senderId
        transaction.type = Int16(type.rawValue)
        transaction.isOutgoing = true
        
        transaction.message = text
        
        prepareAndSendChatTransaction(transaction, in: context, recipientId: recipientId, type: type, keypair: keypair, completion: completion)
    }
    
    private func sendRichMessage(richContent: [String:String], richType: String, senderId: String, recipientId: String, keypair: Keypair, completion: @escaping (ChatsProviderResult) -> Void) {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = stack.container.viewContext
        
        let type = ChatType.richMessage
        
        let transaction = RichMessageTransaction(context: context)
        transaction.date = Date() as NSDate
        transaction.recipientId = recipientId
        transaction.senderId = senderId
        transaction.type = Int16(type.rawValue)
        transaction.isOutgoing = true
        
        transaction.richContent = richContent
        transaction.richType = richType
        
        transaction.transactionStatus = richProviders[richType] != nil ? .notInitiated : nil
        
        prepareAndSendChatTransaction(transaction, in: context, recipientId: recipientId, type: type, keypair: keypair, completion: completion)
    }
    
    
    /// Transaction must be in passed context
    private func prepareAndSendChatTransaction(_ transaction: ChatTransaction, in context: NSManagedObjectContext, recipientId: String, type: ChatType, keypair: Keypair, completion: @escaping (ChatsProviderResult) -> Void) {
        // MARK: 1. Get account
        let accountsGroup = DispatchGroup()
        accountsGroup.enter()
        
        var result: AccountsProviderResult! = nil
        accountsProvider.getAccount(byAddress: recipientId) { r in
            result = r
            accountsGroup.leave()
        }
        
        accountsGroup.wait()
        
        let recipientAccount: CoreDataAccount
        switch result! {
        case .success(let account):
            recipientAccount = account
            
        case .notFound, .invalidAddress:
            completion(.failure(.accountNotFound(recipientId)))
            return
            
        case .serverError(let error):
            completion(.failure(.serverError(error)))
            return
            
        case .networkError(_):
            completion(.failure(ChatsProviderError.networkError))
            return
        }
        
        guard let recipientPublicKey = recipientAccount.publicKey else {
            completion(.failure(.accountNotFound(recipientId)))
            return
        }
        
        // MARK: 2. Get Chatroom
        guard let id = recipientAccount.chatroom?.objectID, let chatroom = context.object(with: id) as? Chatroom else {
            completion(.failure(.accountNotFound(recipientId)))
            return
        }
        
        // MARK: 3. Prepare transaction
        transaction.transactionId = UUID().uuidString
        transaction.blockId = UUID().uuidString
        transaction.statusEnum = MessageStatus.pending
        
        chatroom.addToTransactions(transaction)
        
        // MARK: 4. Last in
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
        
        // MARK: 5. Save unconfirmed transaction
        do {
            try context.save()
        } catch {
            completion(.failure(.internalError(error)))
            return
        }
        
        // MARK: 6. Send
        sendTransaction(transaction, type: type, keypair: keypair, recipientPublicKey: recipientPublicKey) { result in
            switch result {
            case .success:
                do {
                    try context.save()
                    completion(.success)
                } catch {
                    completion(.failure(.internalError(error)))
                }
                
            case .failure(let error):
                try? context.save()
                completion(.failure(error))
            }
        }
    }
    
    func retrySendMessage(_ message: ChatTransaction, completion: @escaping (ChatsProviderRetryCancelResult) -> Void) {
		// MARK: 0. Prepare
		switch message.statusEnum {
		case .delivered, .pending:
			completion(.invalidTransactionStatus(message.statusEnum))
			return
			
		case .failed:
			break
		}
		
		guard let keypair = accountService.keypair else {
			completion(.failure(.notLogged))
			return
		}
		
		guard let recipientPublicKey = message.chatroom?.partner?.publicKey else {
			completion(.failure(.accountNotFound(message.recipientId ?? "")))
			return
		}
		
		// MARK: 1. Prepare private context
		let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		privateContext.parent = stack.container.viewContext
		
		guard let transaction = privateContext.object(with: message.objectID) as? MessageTransaction else {
			completion(.failure(.notLogged)) //
			return
		}
		
		// MARK: 2. Update transaction
		transaction.date = Date() as NSDate
		transaction.statusEnum = .pending
		
		if let chatroom = transaction.chatroom {
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
		
		try? privateContext.save()
		
		
		// MARK: 3. Send
		sendTransaction(transaction, type: .message, keypair: keypair, recipientPublicKey: recipientPublicKey) { result in
			switch result {
			case .success:
				do {
					try privateContext.save()
					completion(.success)
				} catch {
					completion(.failure(.internalError(error)))
				}
				
			case .failure(let error):
				try? privateContext.save()
				completion(.failure(error))
			}
		}
    }
    
    // MARK: - Delete local message
	func cancelMessage(_ message: ChatTransaction, completion: @escaping (ChatsProviderRetryCancelResult) -> Void) {
		// MARK: 0. Prepare
		switch message.statusEnum {
		case .delivered, .pending:
			// We can't cancel sent transactions
			completion(.invalidTransactionStatus(message.statusEnum))
			return
			
		case .failed:
			break
		}
		
		// MARK: 1. Find. Destroy. Save.
		let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		privateContext.parent = stack.container.viewContext
		
		privateContext.delete(privateContext.object(with: message.objectID))
		
		do {
			try privateContext.save()
			completion(.success)
		} catch {
			completion(.failure(.internalError(error)))
			return
		}
	}
	
	
	// MARK: - Logic
	
	/// Send transaction.
	///
	/// If success - update transaction's id and add it to unconfirmed transactions.
	/// If fails - set transaction status to .failed
	private func sendTransaction(_ transaction: ChatTransaction, type: ChatType, keypair: Keypair, recipientPublicKey: String, completion: @escaping (ChatsProviderResult) -> Void) {
		// MARK: 0. Prepare
		guard let senderId = transaction.senderId,
			let recipientId = transaction.recipientId else {
			completion(.failure(.accountNotFound(recipientPublicKey)))
				return
		}
		
		// MARK: 1. Encode
		guard let text = transaction.serializedMessage(), let encodedMessage = adamantCore.encodeMessage(text, recipientPublicKey: recipientPublicKey, privateKey: keypair.privateKey) else {
			completion(.failure(.dependencyError("Failed to encode message")))
			return
		}
		
		// MARK: 2. Send
		apiService.sendMessage(senderId: senderId, recipientId: recipientId, keypair: keypair, message: encodedMessage.message, type: type, nonce: encodedMessage.nonce) { result in
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
				transaction.statusEnum = MessageStatus.failed
				
				let serviceError: ChatsProviderError
				switch error {
				case .networkError(_):
					serviceError = .networkError
					
				case .accountNotFound:
					serviceError = .accountNotFound(recipientId)
					
				case .notLogged:
					serviceError = .notLogged
					
				case .serverError(let e):
					serviceError = .serverError(AdamantError(message: e))
					
				case .internalError(let message, let e):
					serviceError = ChatsProviderError.internalError(AdamantError(message: message, error: e))
				}
				
				completion(.failure(serviceError))
			}
		}
	}
}


// MARK: - Getting messages
extension AdamantChatsProvider {
	func getChatroomsController() -> NSFetchedResultsController<Chatroom> {
		let request: NSFetchRequest<Chatroom> = NSFetchRequest(entityName: Chatroom.entityName)
		request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false),
								   NSSortDescriptor(key: "title", ascending: true)]
		request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
			NSPredicate(format: "partner!=nil"),
			NSPredicate(format: "isHidden = false")])
		let controller = NSFetchedResultsController(fetchRequest: request, managedObjectContext: stack.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
		
		return controller
	}
	
	func getChatController(for chatroom: Chatroom) -> NSFetchedResultsController<ChatTransaction> {
		guard let context = chatroom.managedObjectContext else {
			fatalError()
		}
		
		let request: NSFetchRequest<ChatTransaction> = NSFetchRequest(entityName: "ChatTransaction")
		request.predicate = NSPredicate(format: "chatroom = %@", chatroom)
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true),
								   NSSortDescriptor(key: "transactionId", ascending: true)]
		let controller = NSFetchedResultsController(fetchRequest: request, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
		
		return controller
	}
	
	func getUnreadMessagesController() -> NSFetchedResultsController<ChatTransaction> {
		let request = NSFetchRequest<ChatTransaction>(entityName: "ChatTransaction")
		request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
			NSPredicate(format: "isUnread == true"),
			NSPredicate(format: "chatroom.isHidden == false")])
		
		request.sortDescriptors = [NSSortDescriptor.init(key: "date", ascending: false),
								   NSSortDescriptor(key: "transactionId", ascending: false)]
		
		let controller = NSFetchedResultsController(fetchRequest: request, managedObjectContext: stack.container.viewContext, sectionNameKeyPath: "chatroom.partner.address", cacheName: nil)
		
		return controller
	}
}


// MARK: - Processing
extension AdamantChatsProvider {
	/// Get new transactions
	///
	/// - Parameters:
	///   - account: for account
	///   - height: last message height. Minimum == 1 !!!
	///   - offset: offset, if greater than 100
	/// - Returns: ammount of new messages was added
	private func getTransactions(senderId: String,
								 privateKey: String,
								 height: Int64?,
								 offset: Int?,
								 dispatchGroup: DispatchGroup,
								 context: NSManagedObjectContext,
								 contextMutatingSemaphore cms: DispatchSemaphore) {
		// Enter 1
		dispatchGroup.enter()
		
		// MARK: 1. Get new transactions
		apiService.getMessageTransactions(address: senderId, height: height, offset: offset) { result in
			defer {
				// Leave 1
				dispatchGroup.leave()
			}
			
			switch result {
			case .success(let transactions):
				if transactions.count == 0 {
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
					
					self.process(messageTransactions: transactions,
								 senderId: senderId,
								 privateKey: privateKey,
								 context: context,
								 contextMutatingSemaphore: cms)
				}
				
				// MARK: 4. Get more transactions
				if transactions.count == self.apiTransactions {
					let newOffset: Int
					if let offset = offset {
						newOffset = offset + self.apiTransactions
					} else {
						newOffset = self.apiTransactions
					}
					
					self.getTransactions(senderId: senderId, privateKey: privateKey, height: height, offset: newOffset, dispatchGroup: dispatchGroup, context: context, contextMutatingSemaphore: cms)
				}
				
			case .failure(let error):
				self.setState(.failedToUpdate(error), previous: .updating)
			}
		}
	}
	
	
	/// - Returns: New unread messagess ids
	private func process(messageTransactions: [Transaction],
						 senderId: String,
						 privateKey: String,
						 context: NSManagedObjectContext,
						 contextMutatingSemaphore: DispatchSemaphore) {
		struct DirectionedTransaction {
			let transaction: Transaction
			let isOut: Bool
		}
		
		// MARK: 1. Gather partner keys
		let mapped = messageTransactions.map({ DirectionedTransaction(transaction: $0, isOut: $0.senderId == senderId) })
		let grouppedTransactions = Dictionary(grouping: mapped, by: { $0.isOut ? $0.transaction.recipientId : $0.transaction.senderId })
		
		
		// MARK: 2. Gather Accounts
		var partners: [CoreDataAccount:[DirectionedTransaction]] = [:]
		
		let request = NSFetchRequest<CoreDataAccount>(entityName: CoreDataAccount.entityName)
		request.fetchLimit = grouppedTransactions.count
		let predicates = grouppedTransactions.keys.map { NSPredicate(format: "address = %@", $0) }
		request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
		
		if let results = try? context.fetch(request) {
			for account in results {
				if let address = account.address, let transactions = grouppedTransactions[address] {
					partners[account] = transactions
				}
			}
		}
		
		// MARK: 2.5 Get accounts, that we did not found.
		if partners.count != grouppedTransactions.keys.count {
			let foundedKeys = partners.keys.compactMap {$0.address}
			let notFound = Set<String>(grouppedTransactions.keys).subtracting(foundedKeys)
			var ids = [NSManagedObjectID]()
			let semaphore = DispatchSemaphore(value: 1)
			let keysGroup = DispatchGroup()
			for address in notFound {
				keysGroup.enter() // Enter 1
				
				accountsProvider.getAccount(byAddress: address) { result in
					defer {
						keysGroup.leave() // Exit 1
					}
					
					if case let .success(account) = result {
						semaphore.wait()
						ids.append(account.objectID)
						semaphore.signal()
					}
				}
			}
			
			keysGroup.wait()
			
			// Get in our context
			for id in ids {
				if let account = context.object(with: id) as? CoreDataAccount, let address = account.address, let transactions = grouppedTransactions[address] {
					partners[account] = transactions
				}
			}
		}
		
		if partners.count != grouppedTransactions.keys.count {
			// TODO: Log this strange thing
			print("Failed to get all accounts: Needed keys:\n\(grouppedTransactions.keys.joined(separator: "\n"))\nFounded Addresses: \(partners.keys.compactMap { $0.address }.joined(separator: "\n"))")
		}
		
		
		// MARK: 3. Process Chatrooms and Transactions
		var height: Int64 = 0
		let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		privateContext.parent = context
		var newMessageTransactions = [ChatTransaction]()
		
		for (account, transactions) in partners {
			// We can't save whole context while we are mass creating MessageTransactions.
			let privateChatroom = privateContext.object(with: account.chatroom!.objectID) as! Chatroom
			
			// MARK: Transactions
			var messages = Set<ChatTransaction>()
			
			for trs in transactions {
				unconfirmedsSemaphore.wait()
				if let objectId = unconfirmedTransactions[trs.transaction.id], let unconfirmed = context.object(with: objectId) as? ChatTransaction {
					confirmTransaction(unconfirmed, id: trs.transaction.id, height: Int64(trs.transaction.height), blockId: trs.transaction.blockId, confirmations: trs.transaction.confirmations)
					let h = Int64(trs.transaction.height)
					if height < h {
						height = h
					}
					
					unconfirmedsSemaphore.signal()
					continue
				} else {
					unconfirmedsSemaphore.signal()
				}
				
				let publicKey: String
				if trs.isOut {
					publicKey = account.publicKey ?? ""
				} else {
					publicKey = trs.transaction.senderPublicKey
				}
				
				if let chatTransaction = chatTransaction(from: trs.transaction, isOutgoing: trs.isOut, publicKey: publicKey, privateKey: privateKey, context: privateContext) {
					if height < chatTransaction.height {
						height = chatTransaction.height
					}
					
					if !trs.isOut {
						newMessageTransactions.append(chatTransaction)
						
						// Preset messages
						if account.isSystem, let address = account.address,
							let messages = AdamantContacts.messagesFor(address: address),
							let messageTransaction = chatTransaction as? MessageTransaction,
                            let key = messageTransaction.message,
							let systemMessage = messages.first(where: { key.range(of: $0.key) != nil })?.value {
							
							switch systemMessage.message {
							case .text(let text):
								messageTransaction.message = text
								
							case .markdownText(let text):
								messageTransaction.message = text
								messageTransaction.isMarkdown = true
								
							case .richMessage(let payload):
								messageTransaction.message = payload.serialized()
							}
							
							messageTransaction.silentNotification = systemMessage.silentNotification
						}
					}
					
					messages.insert(chatTransaction)
				}
			}
			
			privateChatroom.addToTransactions(messages as NSSet)
		}
		
		
		// MARK: 4. Unread messagess
		if let readedLastHeight = readedLastHeight {
			let unreadTransactions = newMessageTransactions.filter { $0.height > readedLastHeight }
			let chatrooms = Dictionary(grouping: unreadTransactions, by: ({ (t: ChatTransaction) -> Chatroom in t.chatroom! }))
			
			for (chatroom, trs) in chatrooms {
				chatroom.hasUnreadMessages = true
				trs.forEach { $0.isUnread = true }
			}
		}
		
		
		// MARK: 5. Dump new transactions
		if privateContext.hasChanges {
			do {
				defer {
					contextMutatingSemaphore.signal()
				}
				
				contextMutatingSemaphore.wait()
				
				try privateContext.save()
			} catch {
				print(error)
			}
		}
		
		
		// MARK: 6. Save to main!
		if context.hasChanges {
			do {
				defer {
					contextMutatingSemaphore.signal()
				}
				
				contextMutatingSemaphore.wait()
				
				try context.save()
				
				// MARK: 6. Update lastTransaction
				let viewContextChatrooms = Set<Chatroom>(partners.keys.compactMap { $0.chatroom }).compactMap { self.stack.container.viewContext.object(with: $0.objectID) as? Chatroom }
				
				DispatchQueue.main.async {
					viewContextChatrooms.forEach { $0.updateLastTransaction() }
				}
			} catch {
				print(error)
			}
		}
		
		
		// MARK 7. Last message height
		highSemaphore.wait()
		if let lastHeight = receivedLastHeight {
			if lastHeight < height {
				self.receivedLastHeight = height
			}
		} else {
			receivedLastHeight = height
		}
		
		highSemaphore.signal()
	}
}


// MARK: - Tools
extension AdamantChatsProvider {
	
	/// Check if message is valid for sending
	func validateMessage(_ message: AdamantMessage) -> ValidateMessageResult {
		switch message {
		case .text(let text), .markdownText(let text):
			if text.count == 0 {
				return .empty
			}
			
			if Double(text.count) * 1.5 > 20000.0 {
				return .tooLong
			}
			
			return .isValid
			
		case .richMessage(let payload):
			let text = payload.serialized()
			
			if text.count == 0 {
				return .empty
			}
			
			if Double(text.count) * 1.5 > 20000.0 {
				return .tooLong
			}
			
			return .isValid
		}
	}
	
	/// Parse raw transaction into CoreData chat transaction
	///
	/// - Parameters:
	///   - transaction: Raw transaction
	///   - currentAddress: logged account address
	///   - privateKey: logged account private key
	///   - context: context to insert parsed transaction to
	/// - Returns: New parsed transaction
	private func chatTransaction(from transaction: Transaction, isOutgoing: Bool, publicKey: String, privateKey: String, context: NSManagedObjectContext) -> ChatTransaction? {
		guard let chat = transaction.asset.chat else {
			return nil
		}
		
        let decodedMessage = adamantCore.decodeMessage(rawMessage: chat.message, rawNonce: chat.ownMessage, senderPublicKey: publicKey, privateKey: privateKey)
        
        let messageTransaction: ChatTransaction
        switch chat.type {
        case .message, .messageOld, .signal, .unknown:
            let transaction = MessageTransaction(entity: MessageTransaction.entity(), insertInto: context)
            transaction.message = decodedMessage
            messageTransaction = transaction
            
        case .richMessage:
            let transaction = RichMessageTransaction(entity: RichMessageTransaction.entity(), insertInto: context)
            
            if let decodedMessage = decodedMessage,
                let data = decodedMessage.data(using: String.Encoding.utf8),
                let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: String],
                let type = json["type"] {
                transaction.richType = type
                transaction.richContent = json
                
                transaction.transactionStatus = richProviders[type] != nil ? .notInitiated : nil
            }
            
            messageTransaction = transaction
        }
        
		messageTransaction.date = transaction.date as NSDate
		messageTransaction.recipientId = transaction.recipientId
		messageTransaction.senderId = transaction.senderId
		messageTransaction.transactionId = String(transaction.id)
		messageTransaction.type = Int16(chat.type.rawValue)
		messageTransaction.height = Int64(transaction.height)
        messageTransaction.isConfirmed = true
		messageTransaction.isOutgoing = isOutgoing
		messageTransaction.blockId = transaction.blockId
		messageTransaction.confirmations = transaction.confirmations
        
        messageTransaction.statusEnum = MessageStatus.delivered
		
		return messageTransaction
	}
	
	
	/// Confirm transactions
	///
	/// - Parameters:
	///   - transaction: Unconfirmed transaction
	///   - id: New transaction id	///   - height: New transaction height
	private func confirmTransaction(_ transaction: ChatTransaction, id: UInt64, height: Int64, blockId: String, confirmations: Int64) {
		if transaction.isConfirmed {
			return
		}
		
		transaction.isConfirmed = true
		transaction.height = height
		transaction.blockId = blockId
		transaction.confirmations = confirmations
		transaction.statusEnum = .delivered
		self.unconfirmedTransactions.removeValue(forKey: id)
		
		if let lastHeight = receivedLastHeight, lastHeight < height {
			self.receivedLastHeight = height
		}
	}
}
