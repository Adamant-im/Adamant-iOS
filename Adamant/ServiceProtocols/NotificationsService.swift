//
//  NotificationsService.swift
//  Adamant
//
//  Created by Anokhov Pavel on 09.03.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation

extension String.adamantLocalized {
	struct notifications {
		static let notificationsDisabled = NSLocalizedString("NotificationsService.NotificationsDisabled", comment: "Notifications: User has disabled notifications. Head him into settings")
		
		static let newMessageTitle = NSLocalizedString("NotificationsService.NewMessage.Title", comment: "Notifications: New message notification title")
		static let newMessageBody = NSLocalizedString("NotificationsService.NewMessage.BodyFormat", comment: "Notifications: new messages notification body. Using %d for amount")
		
		static let newTransferTitle = NSLocalizedString("NotificationsService.NewTransfer.Title", comment: "Notifications: New transfer transaction title")
		static let newTransferBody = NSLocalizedString("NotificationsService.NewTransfer.BodyFormat", comment: "Notifications: New transfer notification body. Using %d for amount")
		
		static let registerRemotesError = NSLocalizedString("NotificationsService.Error.RegistrationRemotesFormat", comment: "Notifications: while registering remote notifications. %@ for description")
		
		private init() {}
	}
}

extension StoreKey {
	struct notificationsService {
		static let notificationsMode = "notifications.mode"
		static let customBadgeNumber = "notifications.number"
		
		private init() {}
	}
}

enum NotificationsMode: Int {
	case disabled
	case backgroundFetch
	case push
	
	var localized: String {
		switch self {
		case .disabled:
			return NSLocalizedString("Notifications.Mode.NotificationsDisabled", comment: "Notifications: Disable notifications")
			
		case .backgroundFetch:
			return NSLocalizedString("Notifications.Mode.BackgroundFetch", comment: "Notifications: Use Background fetch notifications")
			
		case .push:
			return NSLocalizedString("Notifications.Mode.ApplePush", comment: "Notifications: Use Apple Push notifications")
		}
	}
}


/// Supported notification types
///
/// - message: text message
/// - transaction: token transaction
/// - custom: other
enum AdamantNotificationType {
	case newMessages(count: Int)
	case newTransactions(count: Int)
	case custom(identifier: String, badge: Int?)
	
	var identifier: String {
		switch self {
		case .newMessages:
			return "newMessages"
			
		case .newTransactions:
			return "newTransactions"
			
		case .custom(let identifier, _):
			return identifier
		}
	}
	
	var badge: Int? {
		switch self {
		case .newMessages(let count):
			return count
			
		case .newTransactions(let count):
			return count
			
		case .custom(_, let badge):
			return badge
		}
	}
}

// MARK: - Notifications
extension Notification.Name {
	struct AdamantNotificationService {
		/// Raised when user has logged out.
		static let notificationsModeChanged = Notification.Name("adamant.notificationService.notificationsMode")
		
		private init() {}
	}
}


extension AdamantUserInfoKey {
	struct NotificationsService {
		static let newNotificationsMode = "adamant.notificationsService.notificationsMode"
		
		private init() {}
	}
}


// MARK: - Protocol
enum NotificationsServiceResult {
	case success
	case denied(error: Error?)
}

protocol NotificationsService: class {
	var notificationsMode: NotificationsMode { get }
	
	func setNotificationsMode(_ mode: NotificationsMode, completion: ((NotificationsServiceResult) -> Void)?)
	
	func showNotification(title: String, body: String, type: AdamantNotificationType)
    func showNotification(title: String, account: LocalAdamantAccount?, body: String, type: AdamantNotificationType)
	
	func setBadge(number: Int?)
	
	func removeAllPendingNotificationRequests()
	func removeAllDeliveredNotifications()
	
	// MARK: Background batch notifications
	func startBackgroundBatchNotifications()
	func stopBackgroundBatchNotifications()
}
