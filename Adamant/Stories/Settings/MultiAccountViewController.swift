//
//  MultiAccountViewController.swift
//  Adamant
//
//  Created by Anton Boyarkin on 23/10/2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit
import Eureka

// MARK: - Localization
extension String.adamantLocalized {
    struct multiAccount {
        static let title = NSLocalizedString("MultiAccount.Title", comment: "MultiAccount: Screen Title")
        
        static let mainAccount = NSLocalizedString("MultiAccount.MainAccount", comment: "MultiAccount: 'Main' label")
        
        static let newAccount = NSLocalizedString("LoginScene.Section.NewAccount", comment: "MultiAccount: 'New account' Title")
        
        private init() {}
    }
}

class MultiAccountViewController: FormViewController {
    // Rows & Sections
    
    private enum Sections {
        case mainAccount
        case accounts
        
        var tag: String {
            switch self {
            case .mainAccount: return "mnacc"
            case .accounts: return "accnts"
            }
        }
    }
    
    private enum Rows {
        case addNew
        case dropAll
        
        var localized: String {
            switch self {
            case .addNew:
                return NSLocalizedString("MultiAccount.AddNew", comment: "MultiAccount: 'Add new' button")
                
            case .dropAll:
                return NSLocalizedString("MultiAccount.DropAll", comment: "MultiAccount: 'Drop All' button")
            }
        }
    }
    
    // MARK: - Dependencies
    
    var accountService: AccountService!
    var notificationsService: NotificationsService!
    var dialogService: DialogService!
    var localAuth: LocalAuthentication!
    var router: Router!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = String.adamantLocalized.multiAccount.title
        
        if let mainAccount = accountService.getMainAccount() {
            let section = Section()
            section <<< AdamantAcountRow() {
                $0.value = mainAccount
                $0.cell.height = { 60 }
                }.cellUpdate({ (cell, _) in
                    if cell.row.value?.address == self.accountService.account?.address {
                        cell.accessoryType = .checkmark
                    } else {
                        cell.accessoryType = .none
                    }
                }).onCellSelection { [weak self] (_, row) in
                    guard let account = row.value, account.address != self?.accountService.account?.address else {
                        return
                    }
                    
                    self?.changeAccount(account.address)
            }
            form +++ section
        }
        
        // MARK: Additional accounts
        
        let section = Section() {
            $0.tag = Sections.accounts.tag
        }
        
        let accounts = accountService.getAdditionalAccounts()
        accounts.forEach { (arg0) in
            let (_, account) = arg0
            section <<< createRowFor(account: account, tag: generateRandomTag())
        }
        
        form +++ section
        // MARK: Buttons
            
        +++ Section()
        
        // Add node
        <<< ButtonRow() {
            $0.title = Rows.addNew.localized
        }.cellSetup { (cell, _) in
            cell.selectionStyle = .gray
        }.onCellSelection { [weak self] (_, _) in
            guard let nav = self?.navigationController, let vc = self?.router.get(scene: AdamantScene.Settings.addAccount) as? AddAccountViewController else {
                return
            }
            vc.delegate = self
            nav.pushViewController(vc, animated: true)
        }.cellUpdate { (cell, _) in
            cell.textLabel?.textColor = UIColor.adamant.primary
        }
            
            
        // MARK: Drop all accounts
            
        +++ Section()
            
        <<< ButtonRow() {
            $0.title = Rows.dropAll.localized
        }.onCellSelection { [weak self] (_, _) in
            self?.accountService.dropAdditionalAccounts()
        }.cellUpdate { (cell, _) in
            cell.textLabel?.textColor = UIColor.adamant.primary
        }
    }
    
    func changeAccount(_ address: String) {
        DispatchQueue.main.async {
            self.dialogService.showProgress(withMessage: nil, userInteractionEnable: false)
        }
        
        accountService.switchToAccount(address: address) { (result) in
            DispatchQueue.main.async {
                self.dialogService.dismissProgress()
            }
        }
    }
    
    private func createRowFor(account: LocalAdamantAccount, tag: String) -> BaseRow {
        let row = AdamantAcountRow() {
            $0.value = account
            $0.tag = tag
            $0.cell.height = { 60 }
            let deleteAction = SwipeAction(style: .destructive, title: "Delete") { [weak self] (action, row, completionHandler) in
                if let account = row.baseValue as? LocalAdamantAccount {
                    if let token = self?.notificationsService.savedToken, let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                        appDelegate.unregisterRemoteNotification(for: account, with: token)
                    }
                    
                    self?.accountService.removeAdditionalAccounts(address: account.address, completion: { (result) in
                        //
                    })
                }
                completionHandler?(true)
            }
            
            $0.trailingSwipe.actions = [deleteAction]
            
            if #available(iOS 11,*) {
                $0.trailingSwipe.performsFirstActionWithFullSwipe = true
            }
            }.cellUpdate({ (cell, _) in
                if let label = cell.textLabel {
                    label.textColor = UIColor.adamant.primary
                }
                if cell.row.value?.address == self.accountService.account?.address {
                    cell.accessoryType = .checkmark
                } else {
                    cell.accessoryType = .none
                }
            }).onCellSelection { [weak self] (_, row) in
                guard let account = row.value, account.address != self?.accountService.account?.address else {
                    return
                }
                
                self?.changeAccount(account.address)
        }
        
        return row
    }
    
    private func generateRandomTag() -> String {
        let capacity = 6
        var nums = [UInt32](reserveCapacity: capacity);
        
        for _ in 0...capacity {
            nums.append(arc4random_uniform(10))
        }
        
        return nums.compactMap { String($0) }.joined()
    }

}

extension MultiAccountViewController: AccountEditorDelegate {
    func accountDidAdded(_ account: LocalAdamantAccount) {
        guard let section = form.sectionBy(tag: Sections.accounts.tag) else {
            return
        }
        
        let row = createRowFor(account: account, tag: generateRandomTag())
        section <<< row
    }
}
