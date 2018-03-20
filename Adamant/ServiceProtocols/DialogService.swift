//
//  DialogService.swift
//  Adamant
//
//  Created by Anokhov Pavel on 07.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit

enum ShareType {
	case copyToPasteboard
	case share
	case generateQr(sharingTip: String?)
	
	var localized: String {
		switch self {
		case .copyToPasteboard:
			return String.adamantLocalized.alert.copyToPasteboard
			
		case .share:
			return String.adamantLocalized.alert.share
			
		case .generateQr:
			return String.adamantLocalized.alert.generateQr
		}
	}
}

extension String.adamantLocalized.alert {
	static let copyToPasteboard = NSLocalizedString("Shared.CopyToPasteboard", comment: "Shared alert 'Copy' button. Used anywhere. Used for copy-paste info.")
	static let share = NSLocalizedString("Shared.Share", comment: "Shared alert 'Share' button. Used anywhere for presenting standart iOS 'Share' menu.")
	static let generateQr = NSLocalizedString("Shared.GenerateQRCode", comment: "Shared alert 'Generate QR' button. Used to generate QR codes with addresses and passphrases. Used with sharing and saving, anywhere.")
}

enum ShareContentType {
	case passphrase
	case address
	
	var excludedActivityTypes: [UIActivityType]? {
		switch self {
		case .passphrase:
			var types: [UIActivityType] = [.postToFacebook,
										   .postToTwitter,
										   .postToWeibo,
										   .message,
										   .mail,
										   .assignToContact,
										   .saveToCameraRoll,
										   .addToReadingList,
										   .postToFlickr,
										   .postToVimeo,
										   .postToTencentWeibo,
										   .airDrop,
										   .openInIBooks]
			
			if #available(iOS 11.0, *) { types.append(.markupAsPDF) }
			return types
			
		case .address:
			return [.assignToContact,
					.addToReadingList,
					.openInIBooks]
		}
	}
}

protocol DialogService: class {
	
	/// Present view controller modally
	func present(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)?)
	
	
	// MARK: - Toast messages
	/// Show pop-up message
	func showToastMessage(_ message: String)
	func dismissToast()
	
	// MARK: - Indicators
	func showProgress(withMessage: String?, userInteractionEnable: Bool)
	func dismissProgress()
	func showSuccess(withMessage: String)
	func showError(withMessage: String)
	
	// MARK: - ActivityControllers
	func presentShareAlertFor(string: String, types: [ShareType], excludedActivityTypes: [UIActivityType]?, animated: Bool, completion: (() -> Void)?)
}
