//
//  AdamantNotificationsService.swift
//  Adamant
//
//  Created by Anokhov Pavel on 09.03.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation
import UIKit
import UserNotifications

extension NotificationsMode {
	func toRaw() -> String {
		return String(self.rawValue)
	}
	
	init?(string: String) {
		guard let int = Int(string: string), let mode = NotificationsMode(rawValue: int) else {
			return nil
		}
		
		self = mode
	}
}

class AdamantNotificationsService: NotificationsService {
	// MARK: Dependencies
	var securedStore: SecuredStore!
	weak var accountService: AccountService?
	
	
	// MARK: Properties
	private(set) var notificationsMode: NotificationsMode = .disabled
	private(set) var customBadgeNumber = 0
	
	private var isBackgroundSession = false
	private var backgroundNotifications = 0
	
	private var preservedBadgeNumber: Int? = nil
    
    var savedToken: String? {
        if let savedHash = securedStore.get(StoreKey.application.deviceTokenHash) {
            return savedHash
        }
        return nil
    }
	
	// MARK: Lifecycle
	init() {
		NotificationCenter.default.addObserver(forName: Notification.Name.AdamantAccountService.userLoggedIn, object: nil, queue: OperationQueue.main) { [weak self] _ in
			UNUserNotificationCenter.current().removeAllDeliveredNotifications()
			UIApplication.shared.applicationIconBadgeNumber = 0
			
			if let securedStore = self?.securedStore, let raw = securedStore.get(StoreKey.notificationsService.notificationsMode), let mode = NotificationsMode(string: raw) {
				self?.setNotificationsMode(mode, completion: nil)
			} else {
				self?.setNotificationsMode(.disabled, completion: nil)
			}
			
			self?.preservedBadgeNumber = nil
		}
		
		NotificationCenter.default.addObserver(forName: Notification.Name.AdamantAccountService.userLoggedOut, object: nil, queue: nil) { [weak self] notification in
            
            if let stayIn = notification.userInfo?["stayIn"] as? Bool, stayIn == true {
                return
            }
            
			self?.setNotificationsMode(.disabled, completion: nil)
			self?.securedStore.remove(StoreKey.notificationsService.notificationsMode)
			self?.preservedBadgeNumber = nil
		}
		
		NotificationCenter.default.addObserver(forName: Notification.Name.AdamantAccountService.stayInChanged, object: nil, queue: nil) { [weak self] notification in
			guard let state = notification.userInfo?[AdamantUserInfoKey.AccountService.newStayInState] as? Bool, state else {
				self?.preservedBadgeNumber = nil
				self?.setBadge(number: nil, force: true)
				return
			}
			
			self?.setBadge(number: self?.preservedBadgeNumber, force: false)
		}
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}


// MARK: - Notifications mode {
extension AdamantNotificationsService {
	func setNotificationsMode(_ mode: NotificationsMode, completion: ((NotificationsServiceResult) -> Void)?) {
		switch mode {
		case .disabled:
			AdamantNotificationsService.configureUIApplicationFor(mode: mode)
			securedStore.remove(StoreKey.notificationsService.notificationsMode)
			notificationsMode = mode
			
			NotificationCenter.default.post(name: Notification.Name.AdamantNotificationService.notificationsModeChanged,
											object: self,
											userInfo: [AdamantUserInfoKey.NotificationsService.newNotificationsMode: mode])
			
			completion?(.success)
			return
			
		case .backgroundFetch, .push:
			authorizeNotifications { [weak self] (success, error) in
				guard success else {
					completion?(.denied(error: error))
					return
				}
				
				AdamantNotificationsService.configureUIApplicationFor(mode: mode)
				self?.securedStore.set(mode.toRaw(), for: StoreKey.notificationsService.notificationsMode)
				self?.notificationsMode = mode
				NotificationCenter.default.post(name: Notification.Name.AdamantNotificationService.notificationsModeChanged,
												object: self,
												userInfo: [AdamantUserInfoKey.NotificationsService.newNotificationsMode: mode])
				completion?(.success)
			}
		}
	}
	
	private func authorizeNotifications(completion: @escaping (Bool, Error?) -> Void) {
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			switch settings.authorizationStatus {
			case .authorized:
				completion(true, nil)
				
			case .denied, .provisional:
				completion(false, nil)
				
			case .notDetermined:
				UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound], completionHandler: { (granted, error) in
					completion(granted, error)
				})
			}
		}
	}
	
	private static func configureUIApplicationFor(mode: NotificationsMode) {
		let callback = {
			switch mode {
			case .disabled:
				UIApplication.shared.unregisterForRemoteNotifications()
				UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalNever)
				
			case .backgroundFetch:
				UIApplication.shared.unregisterForRemoteNotifications()
				UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
				
			case .push:
				UIApplication.shared.registerForRemoteNotifications()
				UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalNever)
			}
		}
		
		if Thread.isMainThread {
			callback()
		} else {
			DispatchQueue.main.sync {
				callback()
			}
		}
	}
}


// MARK: - Posting & removing Notifications
extension AdamantNotificationsService {
	func showNotification(title: String, body: String, type: AdamantNotificationType) {
		self.showNotification(title: title, account: nil, body: body, type: type)
	}
    
    func showNotification(title: String, account: LocalAdamantAccount?, body: String, type: AdamantNotificationType) {
        var identifier = type.identifier
        
        let content = UNMutableNotificationContent()
        content.title = title
        if let account = account {
            content.subtitle = account.getNameOrAddress()
            content.userInfo["address"] = account.address
            
            identifier += "::\(account.address)"
        }
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName("notification.mp3"))
        
        if let number = type.badge {
            if Thread.isMainThread {
                content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + backgroundNotifications + number)
            } else {
                DispatchQueue.main.sync {
                    content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + backgroundNotifications + number)
                }
            }
            
            if isBackgroundSession {
                backgroundNotifications += number
            }
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print(error)
            }
        }
    }
	
	func setBadge(number: Int?) {
		setBadge(number: number, force: false)
	}
	
	private func setBadge(number: Int?, force: Bool) {
		if !force {
			guard let stayIn = accountService?.hasStayInAccount, stayIn else {
				preservedBadgeNumber = number
				return
			}
		}
		
		let appIconBadgeNumber: Int
		
		if let number = number {
			customBadgeNumber = number
			appIconBadgeNumber = number
			securedStore.set(String(number), for: StoreKey.notificationsService.customBadgeNumber)
		} else {
			customBadgeNumber = 0
			appIconBadgeNumber = 0
			securedStore.remove(StoreKey.notificationsService.customBadgeNumber)
		}
		
		if Thread.isMainThread {
			UIApplication.shared.applicationIconBadgeNumber = appIconBadgeNumber
		} else {
			DispatchQueue.main.async {
				UIApplication.shared.applicationIconBadgeNumber = appIconBadgeNumber
			}
		}
	}
	
	func removeAllPendingNotificationRequests() {
		UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
		UIApplication.shared.applicationIconBadgeNumber = customBadgeNumber
	}
	
	func removeAllDeliveredNotifications() {
		UNUserNotificationCenter.current().removeAllDeliveredNotifications()
		UIApplication.shared.applicationIconBadgeNumber = customBadgeNumber
	}
}


// MARK: - Background batch notifications
extension AdamantNotificationsService {
	func startBackgroundBatchNotifications() {
		isBackgroundSession = true
		backgroundNotifications = 0
	}
	
	func stopBackgroundBatchNotifications() {
		isBackgroundSession = false
		backgroundNotifications = 0
	}
}
