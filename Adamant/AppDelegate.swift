//
//  AppDelegate.swift
//  Adamant
//
//  Created by Anokhov Pavel on 05.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit
import Swinject
import CryptoSwift
import CoreData
import UserNotifications

// MARK: - Constants
extension String.adamantLocalized {
	struct tabItems {
		static let account = NSLocalizedString("Tabs.Account", comment: "Main tab bar: Account page")
		static let chats = NSLocalizedString("Tabs.Chats", comment: "Main tab bar: Chats page")
		static let settings = NSLocalizedString("Tabs.Settings", comment: "Main tab bar: Settings page")
	}
	
	struct application {
		static let deviceTokenSendFailed = NSLocalizedString("Application.deviceTokenErrorFormat", comment: "Application: Failed to send deviceToken to ANS error format. %@ for error description")
	}
}

extension StoreKey {
	struct application {
		static let deviceTokenHash = "app.deviceTokenHash"
		
		private init() {}
	}
}


// MARK: - Resources
struct AdamantResources {
	static let jsCore = Bundle.main.url(forResource: "adamant-core", withExtension: "js")!
	static let coreDataModel = Bundle.main.url(forResource: "ChatModels", withExtension: "momd")!
	
	static let nodes: [Node] = [
		Node(scheme: .https, host: "endless.adamant.im", port: nil),
		Node(scheme: .https, host: "clown.adamant.im", port: nil),
		Node(scheme: .https, host: "lake.adamant.im", port: nil),
//		Node(scheme: .http, host: "80.211.177.181", port: nil), // Bugged one
//		Node(scheme: .http, host: "163.172.183.198", port: nil) // Testnet
	]
    
    static let ethServers = [
//        "https://ethnode1.adamant.im/"
        "https://ropsten.infura.io/"  // test network
    ]
	
	// Addresses
	static let supportEmail = "ios@adamant.im"
	static let ansReadmeUrl = "https://github.com/Adamant-im/AdamantNotificationService/blob/master/README.md"
	
	// Contacts
	struct contacts {
		static let adamantBountyWallet = "U15423595369615486571"
		static let adamantIco = "U7047165086065693428"
		static let iosSupport = "U15738334853882270577"
		
		static let ansAddress = "U10629337621822775991"
		static let ansPublicKey = "188b24bd116a556ac8ba905bbbdaa16e237dfb14269f5a4f9a26be77537d977c"
		
		private init() {}
	}
    
    // Explorers
    static let adamantExplorerAddress = "https://explorer.adamant.im/tx/"
//    static let ethereumExplorerAddress = "https://etherscan.io/tx/"
    static let ethereumExplorerAddress = "https://ropsten.etherscan.io/tx/" // Testnet
	
	private init() {}
}


// MARK: - Application
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
	var window: UIWindow?
	var repeater: RepeaterService!
	var container: Container!
	
	// MARK: Dependencies
	var accountService: AccountService!
	var notificationService: NotificationsService!
    var dialogService: DialogService!
    var addressBookService: AddressBookService!

	// MARK: - Lifecycle
	
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		// MARK: 1. Initiating Swinject
		container = Container()
		container.registerAdamantServices()
		accountService = container.resolve(AccountService.self)
		notificationService = container.resolve(NotificationsService.self)
        dialogService = container.resolve(DialogService.self)
        addressBookService = container.resolve(AddressBookService.self)
		
		// MARK: 2. Init UI
		window = UIWindow(frame: UIScreen.main.bounds)
		window!.rootViewController = UITabBarController()
		window!.rootViewController?.view.backgroundColor = .white
		window!.makeKeyAndVisible()
		window!.tintColor = UIColor.adamant.primary
		
		
		// MARK: 3. Show login
		
		guard let router = container.resolve(Router.self) else {
			fatalError("Failed to get Router")
		}
		
		let login = router.get(scene: AdamantScene.Login.login)
		window!.rootViewController?.present(login, animated: false, completion: nil)
		
		// MARK: 4. Prepare pages
		if let tabbar = window?.rootViewController as? UITabBarController {
			let chatListRoot = router.get(scene: AdamantScene.Chats.chatList)
			let chatList = UINavigationController(rootViewController: chatListRoot)
			chatList.tabBarItem.title = String.adamantLocalized.tabItems.chats
			chatList.tabBarItem.image = #imageLiteral(resourceName: "chats_tab")
			
			let accountRoot = router.get(scene: AdamantScene.Account.account)
			let account = UINavigationController(rootViewController: accountRoot)
			account.tabBarItem.title = String.adamantLocalized.tabItems.account
			account.tabBarItem.image = #imageLiteral(resourceName: "account-tab")
			
			chatList.tabBarItem.badgeColor = UIColor.adamant.primary
			account.tabBarItem.badgeColor = UIColor.adamant.primary
			
			tabbar.setViewControllers([chatList, account], animated: false)
		}
		
		
		// MARK: 5 Reachability & Autoupdate
		repeater = RepeaterService()
		
		// Configure reachability
		if let reachability = container.resolve(ReachabilityMonitor.self) {
			reachability.start()
			
			switch reachability.connection {
			case .cellular, .wifi:
                dialogService.dissmisNoConnectionNotification()
				break
				
			case .none:
                dialogService.showNoConnectionNotification()
				repeater.pauseAll()
			}
			
			NotificationCenter.default.addObserver(forName: Notification.Name.AdamantReachabilityMonitor.reachabilityChanged, object: reachability, queue: nil) { [weak self] notification in
				guard let connection = notification.userInfo?[AdamantUserInfoKey.ReachabilityMonitor.connection] as? AdamantConnection,
					let repeater = self?.repeater else {
						return
				}
				
				switch connection {
				case .cellular, .wifi:
                    self?.dialogService.dissmisNoConnectionNotification()
					repeater.resumeAll()
					
				case .none:
                    self?.dialogService.showNoConnectionNotification()
					repeater.pauseAll()
				}
			}
		}
		
		// Register repeater services
		if let chatsProvider = container.resolve(ChatsProvider.self) {
			repeater.registerForegroundCall(label: "chatsProvider", interval: 3, queue: .global(qos: .utility), callback: chatsProvider.update)
		} else {
			dialogService.showError(withMessage: "Failed to register ChatsProvider autoupdate. Please, report a bug", error: nil)
		}
		
		if let transfersProvider = container.resolve(TransfersProvider.self) {
			repeater.registerForegroundCall(label: "transfersProvider", interval: 15, queue: .global(qos: .utility), callback: transfersProvider.update)
		} else {
			dialogService.showError(withMessage: "Failed to register TransfersProvider autoupdate. Please, report a bug", error: nil)
		}
		
		if let accountService = container.resolve(AccountService.self) {
			repeater.registerForegroundCall(label: "accountService", interval: 15, queue: .global(qos: .utility), callback: accountService.update)
		} else {
			dialogService.showError(withMessage: "Failed to register AccountService autoupdate. Please, report a bug", error: nil)
		}
		
		if let addressBookService = container.resolve(AddressBookService.self) {
			repeater.registerForegroundCall(label: "addressBookService", interval: 15, queue: .global(qos: .utility), callback: addressBookService.update)
		} else {
			dialogService.showError(withMessage: "Failed to register AddressBookService autoupdate. Please, report a bug", error: nil)
		}
		
		
		// MARK: 6. Logout reset
		NotificationCenter.default.addObserver(forName: Notification.Name.AdamantAccountService.userLoggedOut, object: nil, queue: OperationQueue.main) { [weak self] _ in
			// On logout, pop all navigators to root.
			guard let tbc = self?.window?.rootViewController as? UITabBarController, let vcs = tbc.viewControllers else {
				return
			}
			
			for case let nav as UINavigationController in vcs {
				nav.popToRootViewController(animated: false)
			}
		}
		
		// MARK: 7. Welcome messages
		NotificationCenter.default.addObserver(forName: Notification.Name.AdamantChatsProvider.initialSyncFinished, object: nil, queue: OperationQueue.main, using: handleWelcomeMessages)
        
        UNUserNotificationCenter.current().delegate = self
		
		return true
	}
	
	// MARK: Timers
	
	func applicationWillResignActive(_ application: UIApplication) {
		repeater.pauseAll()
	}
    
	func applicationDidEnterBackground(_ application: UIApplication) {
		repeater.pauseAll()
		addressBookService.saveIfNeeded()
	}
	
	// MARK: Notifications
	
	func applicationDidBecomeActive(_ application: UIApplication) {
		if accountService.account != nil {
			notificationService.removeAllDeliveredNotifications()
		}
		
		if let connection = container.resolve(ReachabilityMonitor.self)?.connection {
			switch connection {
			case .wifi, .cellular:
				repeater.resumeAll()
				
			case .none:
				break
			}
		} else {
			repeater.resumeAll()
		}
	}
}

// MARK: - Remote notifications
extension AppDelegate: UNUserNotificationCenterDelegate {
	private struct RegistrationPayload: Codable {
		let token: String
		let action: String = "add"
        
		#if DEBUG
			let provider: String = "apns-sandbox"
		#else
			let provider: String = "apns"
		#endif
	}
    
    private struct UnRegistrationPayload: Codable {
        let token: String
        let action: String = "remove"
        
        #if DEBUG
        let provider: String = "apns-sandbox"
        #else
        let provider: String = "apns"
        #endif
    }
	
	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let accounts = Array(accountService.getAccounts().values)
        
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        // MARK: 1. Checking, if device token had not changed
        guard let securedStore = container.resolve(SecuredStore.self) else {
            fatalError("can't get secured store to get device token hash")
        }
        
        let tokenHash = token//.md5()
        
        if let savedHash = securedStore.get(StoreKey.application.deviceTokenHash), tokenHash == savedHash {
            return
        } else {
            securedStore.set(tokenHash, for: StoreKey.application.deviceTokenHash)
        }
        
        for account in accounts {
            self.registerRemoteNotification(for: account, with: token)
        }
	}
	
	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
		if let service = container.resolve(DialogService.self) {
			service.showError(withMessage: String.localizedStringWithFormat(String.adamantLocalized.notifications.registerRemotesError, error.localizedDescription), error: error)
		}
	}
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Determine the user action
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            if let address = response.notification.request.content.userInfo["address"] as? String {
                if let securedStore = container.resolve(SecuredStore.self) {
                    if let account = securedStore.getAccount(by: address) {
                        securedStore.setLastUsedAccount(account)
                    }
                }
            }
            
        default:
            print("Unknown action")
        }
        completionHandler()
    }
}


// MARK: - Background Fetch
extension AppDelegate {
	func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		let container = Container()
		container.registerAdamantBackgroundFetchServices()
		
		guard let notificationsService = container.resolve(NotificationsService.self) else {
				UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalNever)
				completionHandler(.failed)
				return
		}
		
		notificationsService.startBackgroundBatchNotifications()
		
		let services: [BackgroundFetchService] = [
			container.resolve(ChatsProvider.self) as! BackgroundFetchService,
			container.resolve(TransfersProvider.self) as! BackgroundFetchService
		]
		
		let group = DispatchGroup()
		let semaphore = DispatchSemaphore(value: 1)
		var results = [FetchResult]()
		
		for service in services {
			group.enter()
			service.fetchBackgroundData(notificationsService: notificationsService) { result in
				defer {
					group.leave()
				}
				
				semaphore.wait()
				results.append(result)
				semaphore.signal()
			}
		}
		
		group.notify(queue: DispatchQueue.global(qos: .utility)) {
			notificationsService.stopBackgroundBatchNotifications()
			
			for result in results {
				switch result {
				case .newData:
					completionHandler(.newData)
					return
					
				case .noData:
					break
					
				case .failed:
					completionHandler(.failed)
					return
				}
			}
			
			completionHandler(.noData)
		}
	}
}


// MARK: - Welcome messages
extension AppDelegate {
	private func handleWelcomeMessages(notification: Notification) {
		guard let stack = container.resolve(CoreDataStack.self), let chatProvider = container.resolve(ChatsProvider.self) else {
			fatalError("Whoa...")
		}
		
		let request = NSFetchRequest<MessageTransaction>(entityName: MessageTransaction.entityName)
		
		let unread: Bool
		if let count = try? stack.container.viewContext.count(for: request), count > 0 {
			unread = false
		} else {
			unread = true
		}
		
		if let welcome = AdamantContacts.adamantBountyWallet.messages["chats.welcome_message"] {
			chatProvider.fakeReceived(message: welcome.message,
									  senderId: AdamantContacts.adamantBountyWallet.name,
									  date: Date.adamantNullDate,
									  unread: unread,
									  silent: welcome.silentNotification,
									  completion: { _ in })
		}
		
		if let ico = AdamantContacts.adamantIco.messages["chats.ico_message"] {
			chatProvider.fakeReceived(message: ico.message,
									  senderId: AdamantContacts.adamantIco.name,
									  date: Date.adamantNullDate,
									  unread: unread,
									  silent: ico.silentNotification,
									  completion: { _ in })
		}
	}
}

// MARK: - Register/Unregisted remote notification
extension AppDelegate {
    func registerRemoteNotification(for account: LocalAdamantAccount, with token: String) {
        // MARK: 1. Preparing message
        let payload: String
        do {
            let data = try JSONEncoder().encode(RegistrationPayload(token: token))
            payload = String(data: data, encoding: String.Encoding.utf8)!
        } catch {
            dialogService.showError(withMessage: "Failed to prepare ANS signal payload", error: error)
            return
        }
        
        // MARK: 2. Send action
        self.sendAction(payload, for: account, with: token)
    }
    
    func unregisterRemoteNotification(for account: LocalAdamantAccount, with token: String) {
        // MARK: 1. Preparing message
        let payload: String
        do {
            let data = try JSONEncoder().encode(UnRegistrationPayload(token: token))
            payload = String(data: data, encoding: String.Encoding.utf8)!
        } catch {
            dialogService.showError(withMessage: "Failed to prepare ANS signal payload", error: error)
            return
        }
        
        // MARK: 2. Send action
        self.sendAction(payload, for: account, with: token)
    }
    
    func sendAction(_ payload: String, for account: LocalAdamantAccount, with token: String) {
        // MARK: 1. Check dependencies
        guard let adamantCore = container.resolve(AdamantCore.self) else {
            fatalError("Can't get AdamantCore to register device token")
        }
        
        guard let apiService = container.resolve(ApiService.self) else {
            fatalError("can't get api service to register device token")
        }
        
        if let keypair = account.getKeyPair() {
            let address = account.address
            
            // MARK: 2. Preparing message
            guard let encodedPayload = adamantCore.encodeMessage(payload, recipientPublicKey: AdamantResources.contacts.ansPublicKey, privateKey: keypair.privateKey) else {
                dialogService.showError(withMessage: "Failed to encode ANS signal. Payload: \(payload)", error: nil)
                return
            }
            
            // MARK: 3. Send signal to ANS
            apiService.sendMessage(senderId: address, recipientId: AdamantResources.contacts.ansAddress, keypair: keypair, message: encodedPayload.message, type: ChatType.signal, nonce: encodedPayload.nonce) { [unowned self] result in
                switch result {
                case .success:
                    return
                    
                case .failure(let error):
                    self.notificationService?.setNotificationsMode(.disabled, completion: nil)
                    self.dialogService.showRichError(error: error)
                }
            }
        }
    }
}
