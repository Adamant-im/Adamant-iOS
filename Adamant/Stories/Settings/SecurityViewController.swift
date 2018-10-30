//
//  SecurityViewController.swift
//  Adamant
//
//  Created by Anokhov Pavel on 04.07.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation
import Eureka
import SafariServices
import Haring

// MARK: - Localization
extension String.adamantLocalized {
	struct security {
		static let title = NSLocalizedString("SecurityPage.Title", comment: "Security: scene title")
		
		static let stayInTurnOff = NSLocalizedString("SecurityPage.DoNotStayLoggedIn", comment: "Security: turn off 'Stay Logged In' confirmation")
		static let biometryOnReason = NSLocalizedString("SecurityPage.UseBiometry", comment: "Security: Authorization reason for turning biometry on")
		static let biometryOffReason = NSLocalizedString("SecurityPage.DoNotUseBiometry", comment: "Security: Authorization reason for turning biometry off")
		
		private init() {}
	}
}

// Eureka uses CustomStringConvertible to represen enums as strings
extension NotificationsMode: CustomStringConvertible {
	var description: String {
		return localized
	}
}


// MARK: - SecurityViewController
class SecurityViewController: FormViewController {
	
	enum PinpadRequest {
		case createPin
		case reenterPin(pin: String)
		case turnOffPin
		case turnOnBiometry
		case turnOffBiometry
	}
	
	// MARK: - Section & Rows
	
	enum Sections {
		case security
        case accounts
		case notifications
		case aboutNotificationTypes
		
		var tag: String {
			switch self {
			case .security: return "ss"
            case .accounts: return "ac"
			case .notifications: return "st"
			case .aboutNotificationTypes: return "ans"
			}
		}
		
		var localized: String {
			switch self {
			case .security: return NSLocalizedString("SecurityPage.Section.Security", comment: "Security: Security section")
            case .accounts: return NSLocalizedString("SecurityPage.Section.Accounts", comment: "Security: Multi Account section")
			case .notifications: return NSLocalizedString("SecurityPage.Section.NotificationsType", comment: "Security: Selected notifications types")
			case .aboutNotificationTypes: return NSLocalizedString("SecurityPage.Section.AboutNotificationTypes", comment: "Security: About Notification types")
			}
		}
	}
	
	enum Rows {
		case generateQr, stayIn, biometry
        case currentAccount
		case notificationsMode
		case description, github
		
		var tag: String {
			switch self {
			case .generateQr: return "qr"
			case .stayIn: return "rs"
			case .biometry: return "rb"
            case .currentAccount: return "crntac"
			case .notificationsMode: return "rn"
			case .description: return "rd"
			case .github: return "git"
			}
		}
		
		var localized: String {
			switch self {
			case .generateQr: return NSLocalizedString("SecurityPage.Row.GenerateQr", comment: "Security: Generate QR with passphrase row")
			case .stayIn: return NSLocalizedString("SecurityPage.Row.StayLoggedIn", comment: "Security: Stay logged option")
			case .biometry: return "" // localAuth.biometryType.localized
            case .currentAccount: return NSLocalizedString("SecurityPage.Row.CurrentAccount", comment: "Security: Current Account option")
			case .notificationsMode: return NSLocalizedString("SecurityPage.Row.Notifications", comment: "Security: Show notifications")
			case .description: return NSLocalizedString("SecurityPage.Row.Notifications.ModesDescription", comment: "Security: Notification modes description. Markdown supported.")
			case .github: return NSLocalizedString("SecurityPage.Row.VisitGithub", comment: "Security: Visit Github")
			}
		}
	}
	
	
	// MARK: - Dependencies
	
	var accountService: AccountService!
	var dialogService: DialogService!
	var notificationsService: NotificationsService!
	var localAuth: LocalAuthentication!
	var router: Router!
	
	
	// MARK: - Properties
	var showLoggedInOptions: Bool {
		return accountService.hasStayInAccount
	}
	
	var showBiometryOptions: Bool {
		switch localAuth.biometryType {
		case .none:
			return false
			
		case .touchID, .faceID:
			return showLoggedInOptions
		}
	}
	
	var pinpadRequest: SecurityViewController.PinpadRequest?
	
	
	// MARK: - Lifecycle
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		navigationItem.title = String.adamantLocalized.security.title
		navigationOptions = .Disabled
		
		if #available(iOS 11.0, *) {
			navigationController?.navigationBar.prefersLargeTitles = true
		}
		
		// MARK: StayIn
		// Generate QR
		let qrRow = LabelRow() {
			$0.title = Rows.generateQr.localized
			$0.tag = Rows.generateQr.tag
			$0.cell.selectionStyle = .gray
		}.cellUpdate({ (cell, _) in
			cell.accessoryType = .disclosureIndicator
		}).onCellSelection { [weak self] (_, _) in
			guard let nav = self?.navigationController, let vc = self?.router.get(scene: AdamantScene.Settings.qRGenerator) else {
				return
			}
			
			nav.pushViewController(vc, animated: true)
		}
		
		// Stay logged in
		let stayInRow = SwitchRow() {
			$0.tag = Rows.stayIn.tag
			$0.title = Rows.stayIn.localized
			$0.value = accountService.hasStayInAccount
		}.onChange { [weak self] row in
			guard let enabled = row.value else {
				return
			}
			
			self?.setStayLoggedIn(enabled: enabled)
		}
		
		// Biometry
		let biometryRow = SwitchRow() {
			$0.tag = Rows.biometry.tag
			$0.title = localAuth.biometryType.localized
			$0.value = accountService.useBiometry
			
			$0.hidden = Condition.function([], { [weak self] _ -> Bool in
				guard let showBiometry = self?.showBiometryOptions else {
					return true
				}
				
				return !showBiometry
			})
		}.onChange { [weak self] row in
			let value = row.value ?? false
			self?.setBiometry(enabled: value)
		}
		
		let stayInSection = Section(Sections.security.localized) {
			$0.tag = Sections.security.tag
		}
		
		stayInSection.append(contentsOf: [qrRow, stayInRow, biometryRow])
		form.append(stayInSection)
        
        // Accounts section
        let accountsSection = Section(Sections.accounts.localized) {
            $0.tag = Sections.accounts.tag
            
            $0.hidden = Condition.function([], { [weak self] _ -> Bool in
                guard let showSection = self?.showLoggedInOptions else {
                    return true
                }
                
                return !showSection
            })
        }
        
        let cuttentAccountRow = AdamantAcountRow() {
            $0.tag = Rows.currentAccount.tag
            $0.value = SavedAccount(name: Rows.currentAccount.localized, address: accountService.account?.address ?? "", passphrase: "")
            }.cellSetup { (cell, _) in
                cell.selectionStyle = .gray
            }.cellUpdate({ (cell, _) in
                cell.accessoryType = .disclosureIndicator
            }).onCellSelection { [weak self] (_, row) in
                guard let nav = self?.navigationController, let vc = self?.router.get(scene: AdamantScene.Settings.multiAccount) else {
                    return
                }
                
                nav.pushViewController(vc, animated: true)
        }
        
        accountsSection.append(cuttentAccountRow)
		form.append(accountsSection)
		
		// MARK: Notifications
		// Type
		let nType = ActionSheetRow<NotificationsMode>() {
			$0.tag = Rows.notificationsMode.tag
			$0.title = Rows.notificationsMode.localized
			$0.selectorTitle = Rows.notificationsMode.localized
			$0.options = [.disabled, .backgroundFetch, .push]
			$0.value = notificationsService.notificationsMode
		}.cellUpdate { (cell, _) in
			cell.accessoryType = .disclosureIndicator
		}.onChange { [weak self] row in
			let mode = row.value ?? NotificationsMode.disabled
			self?.setNotificationMode(mode)
		}
		
		// Section
		let notificationsSection = Section(Sections.notifications.localized) {
			$0.tag = Sections.notifications.tag
			
			$0.hidden = Condition.function([], { [weak self] _ -> Bool in
				guard let showNotifications = self?.showLoggedInOptions else {
					return true
				}
				
				return !showNotifications
			})
		}
		
		notificationsSection.append(nType)
		form.append(notificationsSection)
		
		
		// MARK: ANS Description
		// Description
		let descriptionRow = TextAreaRow() {
			$0.textAreaHeight = .dynamic(initialTextViewHeight: 44)
			$0.tag = Rows.description.tag
		}.cellUpdate { (cell, _) in
			cell.textView.isSelectable = false
			cell.textView.isEditable = false
			
			let parser = MarkdownParser(font: UIFont.systemFont(ofSize: UIFont.systemFontSize))
			cell.textView.attributedText = parser.parse(Rows.description.localized)
		}
		
		// Github readme
		let githubRow = LabelRow() {
			$0.tag = Rows.github.tag
			$0.title = Rows.github.localized
			$0.cell.imageView?.image = #imageLiteral(resourceName: "row_github")
			$0.cell.imageView?.tintColor = UIColor.adamant.tableRowIcons
		}.cellSetup { (cell, _) in
			cell.selectionStyle = .gray
		}.cellUpdate({ (cell, _) in
			cell.accessoryType = .disclosureIndicator
		}).onCellSelection { [weak self] (_, row) in
			guard let url = URL(string: AdamantResources.ansReadmeUrl) else {
				fatalError("Failed to build ANS URL")
			}
			
			let safari = SFSafariViewController(url: url)
			safari.preferredControlTintColor = UIColor.adamant.primary
			self?.present(safari, animated: true, completion: nil)
		}
		
		let ansSection = Section(Sections.aboutNotificationTypes.localized) {
			$0.tag = Sections.aboutNotificationTypes.tag
			
			$0.hidden = Condition.function([], { [weak self] _ -> Bool in
				guard let showNotifications = self?.showLoggedInOptions else {
					return true
				}
				
				return !showNotifications
			})
		}
		
		ansSection.append(contentsOf: [descriptionRow, githubRow])
		form.append(ansSection)
		
		
		// MARK: Notifications
		NotificationCenter.default.addObserver(forName: Notification.Name.AdamantAccountService.userLoggedIn, object: nil, queue: OperationQueue.main) { [weak self] _ in
			self?.reloadForm()
		}
		
		NotificationCenter.default.addObserver(forName: Notification.Name.AdamantAccountService.stayInChanged, object: nil, queue: OperationQueue.main) { [weak self] notification in
			self?.reloadForm()
		}
		
		NotificationCenter.default.addObserver(forName: Notification.Name.AdamantNotificationService.notificationsModeChanged, object: nil, queue: OperationQueue.main) { [weak self] notification in
			guard let newMode = notification.userInfo?[AdamantUserInfoKey.NotificationsService.newNotificationsMode] as? NotificationsMode else {
				return
			}
			
			guard let row: ActionSheetRow<NotificationsMode> = self?.form.rowBy(tag: Rows.notificationsMode.tag) else {
				return
			}
			
			row.value = newMode
			row.updateCell()
		}
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if let indexPath = tableView.indexPathForSelectedRow {
			tableView.deselectRow(at: indexPath, animated: animated)
		}
	}
	
	private func reloadForm() {
		if let row: SwitchRow = form.rowBy(tag: Rows.stayIn.tag) {
			row.value = accountService.hasStayInAccount
		}
		
		if let row: SwitchRow = form.rowBy(tag: Rows.biometry.tag) {
			row.value = accountService.hasStayInAccount && accountService.useBiometry
			row.evaluateHidden()
		}
        
        if let section = form.sectionBy(tag: Sections.accounts.tag) {
            section.evaluateHidden()
        }
		
		if let section = form.sectionBy(tag: Sections.notifications.tag) {
			section.evaluateHidden()
		}
		
		if let section = form.sectionBy(tag: Sections.aboutNotificationTypes.tag) {
			section.evaluateHidden()
		}
	}
}
