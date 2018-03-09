//
//  AppDelegate.swift
//  Adamant
//
//  Created by Anokhov Pavel on 05.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit
import Swinject
import SwinjectStoryboard

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
	
	var window: UIWindow?
	var repeater: RepeaterService!
	
	weak var accountService: AccountService?
	weak var notificationService: NotificationsService?

	// MARK: - Lifecycle
	
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
		// MARK: 1. Initiating Swinject
		let container = SwinjectStoryboard.defaultContainer
		Container.loggingFunction = nil // Logging currently not supported with SwinjectStoryboards.
		container.registerAdamantServices()
		container.registerAdamantAccountStory()
		container.registerAdamantLoginStory()
		container.registerAdamantChatsStory()
		container.registerAdamantSettingsStory()
		
		accountService = container.resolve(AccountService.self)
		notificationService = container.resolve(NotificationsService.self)
		
		
		// MARK: 2. Prepare UI
		self.window = UIWindow(frame: UIScreen.main.bounds)
		self.window!.rootViewController = UITabBarController()
		self.window!.rootViewController?.view.backgroundColor = .white
		self.window!.makeKeyAndVisible()
		
		self.window!.tintColor = UIColor.adamantPrimary
		
		guard let router = container.resolve(Router.self) else {
			fatalError("Failed to get Router")
		}
		
		if let tabbar = self.window!.rootViewController as? UITabBarController {
			let account = router.get(story: .Account).instantiateInitialViewController()!
			let chats = router.get(story: .Chats).instantiateInitialViewController()!
			let settings = router.get(story: .Settings).instantiateInitialViewController()!

			account.tabBarItem.badgeColor = UIColor.adamantPrimary
			chats.tabBarItem.badgeColor = UIColor.adamantPrimary
			settings.tabBarItem.badgeColor = UIColor.adamantPrimary
			
			tabbar.setViewControllers([account, chats, settings], animated: false)
		}

		
		// MARK: 3. Initiate login
		self.window!.rootViewController?.present(router.get(scene: .Login), animated: false, completion: nil)
		
		
		// MARK: 4 Autoupdate
		let chatsProvider = container.resolve(ChatsProvider.self)!
		repeater = RepeaterService()
		repeater.registerForegroundCall(label: "chatsProvider", interval: 3, queue: DispatchQueue.global(qos: .utility), callback: chatsProvider.update)
		
		
		// MARK: 4. Notifications
		if let service = container.resolve(NotificationsService.self) {
			if service.notificationsEnabled {
				UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalMinimum)
			} else {
				UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalNever)
			}
			
			NotificationCenter.default.addObserver(forName: Notification.Name.adamantShowNotificationsChanged, object: service, queue: OperationQueue.main) { _ in
				if service.notificationsEnabled {
					UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalMinimum)
				} else {
					UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalNever)
				}
			}
		}
		
		
		// MARK: 5. Logout reset
		NotificationCenter.default.addObserver(forName: Notification.Name.adamantUserLoggedOut, object: nil, queue: OperationQueue.main) { [weak self] _ in
			// On logout, pop all navigators to root.
			guard let tbc = self?.window?.rootViewController as? UITabBarController, let vcs = tbc.viewControllers else {
				return
			}
			
			for case let nav as UINavigationController in vcs {
				nav.popToRootViewController(animated: false)
			}
		}
		
		return true
	}
	
	// MARK: Timers
	
	func applicationWillResignActive(_ application: UIApplication) {
		repeater.pauseAll()
	}
	
	func applicationDidEnterBackground(_ application: UIApplication) {
		repeater.pauseAll()
	}
	
	func applicationDidBecomeActive(_ application: UIApplication) {
		repeater.resumeAll()
		
		if accountService?.account != nil {
			notificationService?.removeAllDeliveredNotifications()
		}
	}
	
	// MARK: Background fetch
	
	func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		let container = Container()
		container.registerAdamantBackgroundFetchServices()
		
		guard let securedStore = container.resolve(SecuredStore.self),
			let apiService = container.resolve(ApiService.self),
			let notificationsService = container.resolve(NotificationsService.self) else {
			UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalNever)
			completionHandler(.failed)
			return
		}
		
		guard let address = securedStore.get(StoreKey.chatProvider.address) else {
			UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalNever)
			completionHandler(.failed)
			return
		}
		
		var lastHeight: Int64?
		if let raw = securedStore.get(StoreKey.chatProvider.receivedLastHeight) {
			lastHeight = Int64(raw)
		} else {
			lastHeight = nil
		}
		
		var notifiedCount = 0
		if let raw = securedStore.get(StoreKey.chatProvider.notifiedLastHeight), let notifiedHeight = Int64(raw), let h = lastHeight {
			if h < notifiedHeight {
				lastHeight = notifiedHeight
				
				if let raw = securedStore.get(StoreKey.chatProvider.notifiedMessagesCount), let count = Int(raw) {
					notifiedCount = count
				}
			}
		}
		
		
		apiService.getChatTransactions(address: address, height: lastHeight, offset: nil) { result in
			switch result {
			case .success(let transactions):
				if transactions.count > 0 {
					let total = transactions.count + notifiedCount
					securedStore.set(String(total), for: StoreKey.chatProvider.notifiedMessagesCount)
					
					if let newLastHeight = transactions.map({$0.height}).sorted().last {
						securedStore.set(String(newLastHeight), for: StoreKey.chatProvider.notifiedLastHeight)
					}
					
					
					notificationsService.showNotification(title: String.adamantLocalized.notifications.newMessageTitle, body: String.localizedStringWithFormat(String.adamantLocalized.notifications.newMessageBody, total), type: .newMessages(count: total))
					completionHandler(.newData)
				} else {
					completionHandler(.noData)
				}
				
			case .failure(_):
				completionHandler(.failed)
			}
		}
	}
}
