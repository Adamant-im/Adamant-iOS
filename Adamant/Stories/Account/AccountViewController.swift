//
//  AccountViewController.swift
//  Adamant
//
//  Created by Anokhov Pavel on 07.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit
import SafariServices

class AccountViewController: UIViewController {
	// MARK: - Constants
	private let cellIdentifier = "cell"
	private let showTransactionsSegue = "showTransactions"
	private let showTransferSegue = "showTransfer"
	
	private enum Sections: Int {
		case account = 0, wallet, actions
		
		static let total = 3
	}
	
	private enum WalletRows: Int {
		case balance, sendTokens, invest
		
		static let total = 3
	}
	
	
	// MARK: - Dependencies
	var accountService: AccountService!
	var dialogService: DialogService!
	
	
	// MARK: - IBOutlets
	@IBOutlet weak var tableView: UITableView!
	
	
	// MARK: - Lifecycle
	
    override func viewDidLoad() {
        super.viewDidLoad()

		tableView.delegate = self
		tableView.dataSource = self
		
		NotificationCenter.default.addObserver(forName: .adamantUserLoggedIn, object: nil, queue: OperationQueue.main) { _ in
			self.tableView.reloadData()
		}
		NotificationCenter.default.addObserver(forName: .adamantUserLoggedOut, object: nil, queue: OperationQueue.main) { _ in
			self.tableView.reloadData()
		}
    }
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if let indexPath = tableView.indexPathForSelectedRow {
			tableView.deselectRow(at: indexPath, animated: animated)
		}
		
		NotificationCenter.default.addObserver(forName: Notification.Name.adamantAccountDataUpdated, object: nil, queue: OperationQueue.main) { _ in
			self.refreshBalanceCell()
		}
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		guard let identifier = segue.identifier else {
			return
		}
		
		switch identifier {
		case showTransactionsSegue:
			if let account = accountService.account?.address, let vc = segue.destination as? TransactionsViewController {
				vc.account = account
			}
			
		case showTransferSegue:
			if let account = accountService.account, let vc = segue.destination as? TransferViewController {
				vc.account = account
			}
			
		default:
			return
		}
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}


// MARK: - UITableView
extension AccountViewController: UITableViewDataSource, UITableViewDelegate {
	func numberOfSections(in tableView: UITableView) -> Int {
		return Sections.total
	}
	
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if accountService.account != nil, let sect = Sections(rawValue: section) {
			switch sect {
			case .account: return 1
			case .wallet: return WalletRows.total
			case .actions: return 1
			}
		} else {
			return 0
		}
	}
	
	func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		return 65
	}
	
	func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
		return UIView()
	}
	
	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		guard let section = Sections(rawValue: indexPath.section) else {
			return
		}
		
		switch section {
		case .account:
			tableView.deselectRow(at: indexPath, animated: true)
			
			guard let address = self.accountService.account?.address else {
				return
			}
			
			let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
			
			alert.addAction(UIAlertAction(title: "Copy To Pasteboard", style: .default, handler: { _ in
				UIPasteboard.general.string = address
				self.dialogService.showToastMessage("\(address)\nCopied To Pasteboard!")
			}))
			
			alert.addAction(UIAlertAction(title: "Share", style: .default, handler: { _ in
				let vc = UIActivityViewController(activityItems: [address], applicationActivities: nil)
				self.present(vc, animated: true)
			}))
			
			alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
			
			present(alert, animated: true)
			
		case .wallet:
			guard let row = WalletRows(rawValue: indexPath.row) else {
				return
				
			}
			
			switch row {
			case .balance:
				performSegue(withIdentifier: showTransactionsSegue, sender: nil)
				
			case .sendTokens:
				performSegue(withIdentifier: showTransferSegue, sender: nil)
				
			case .invest:
				guard let address = accountService.account?.address,
					let url = URL(string: "https://adamant.im/ico/?wallet=\(address)") else {
					return
				}
				
				let safari = SFSafariViewController(url: url)
				safari.preferredControlTintColor = UIColor.adamantPrimary
				present(safari, animated: true, completion: nil)
				return
			}
			
		case .actions:
			guard let address = accountService.account?.address else {
				return
			}
			
			let alert = UIAlertController(title: "Logout from \(address)?", message: nil, preferredStyle: .alert)
			let cancel = UIAlertAction(title: "Cancel", style: .cancel) { _ in
				self.tableView.deselectRow(at: indexPath, animated: true)
			}
			let logout = UIAlertAction(title: "Logout", style: .default) { _ in
				self.accountService.logoutAndPresentLoginStoryboard(animated: true, authorizationFinishedHandler: nil)
			}
			
			alert.addAction(cancel)
			alert.addAction(logout)
			present(alert, animated: true, completion: nil)
		}
	}
}


// MARK: - UITableView Cells
extension AccountViewController {
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard let account = accountService.account,
			let section = Sections(rawValue: indexPath.section) else {
				return UITableViewCell(style: .default, reuseIdentifier: nil)
		}
		
		let cell: UITableViewCell
		if let c = tableView.dequeueReusableCell(withIdentifier: cellIdentifier) {
			cell = c
		} else {
			cell = UITableViewCell(style: .value1, reuseIdentifier: cellIdentifier)
			cell.accessoryType = .disclosureIndicator
			cell.textLabel?.font = UIFont.adamantPrimary(size: 17)
			cell.detailTextLabel?.font = UIFont.adamantPrimary(size: 17)
			
			cell.textLabel?.textColor = UIColor.adamantPrimary
			cell.detailTextLabel?.textColor = UIColor.adamantPrimary
			
			cell.imageView?.tintColor = UIColor.adamantChatIcons
		}
		
		switch section {
		case .account:
			cell.textLabel?.text = account.address
			cell.detailTextLabel?.text = nil
			cell.imageView?.image = #imageLiteral(resourceName: "account")
			
		case .wallet:
			guard let row = WalletRows(rawValue: indexPath.row) else {
				break
			}
			
			switch row {
			case .balance:
				cell.textLabel?.text = "Balance"
				cell.detailTextLabel?.text = AdamantUtilities.format(balance: account.balance)
				cell.imageView?.image = nil
				
			case .sendTokens:
				cell.textLabel?.text = "Send Tokens"
				cell.detailTextLabel?.text = nil
				cell.imageView?.image = nil
				
			case .invest:
				cell.textLabel?.text = "Invest in ICO"
				cell.detailTextLabel?.text = nil
				cell.imageView?.image = nil
			}
			
		case .actions:
			cell.textLabel?.text = "Logout"
			cell.detailTextLabel?.text = nil
			cell.imageView?.image = nil
		}
		
		return cell
	}
	
	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		guard let sect = Sections(rawValue: section) else {
			return nil
		}
		
		switch sect {
		case .account:
			return "Account"
			
		case .wallet:
			return "Wallet"
			
		case .actions:
			return "Actions"
		}
	}
	
	private func refreshBalanceCell() {
		guard let account = accountService.account,
			let cell = tableView.cellForRow(at: IndexPath(row: WalletRows.balance.rawValue, section: Sections.wallet.rawValue)) else {
			return
		}
		
		cell.detailTextLabel?.text = AdamantUtilities.format(balance: account.balance)
	}
}
