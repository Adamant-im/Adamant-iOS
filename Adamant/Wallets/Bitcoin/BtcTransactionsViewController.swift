//
//  BtcTransactionsViewController.swift
//  Adamant
//
//  Created by Anton Boyarkin on 30/01/2019.
//  Copyright © 2019 Adamant. All rights reserved.
//

import Foundation
import BitcoinKit

class BtcTransactionsViewController: TransactionsListViewControllerBase {
    
    // MARK: - Dependencies
    var btcWalletService: BtcWalletService!
    var dialogService: DialogService!
    var router: Router!
    
    // MARK: - Properties
    var transactions: [Payment] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.refreshControl.beginRefreshing()
        
        currencySymbol = BtcWalletService.currencySymbol
        
        handleRefresh(self.refreshControl)
    }
    
    override func handleRefresh(_ refreshControl: UIRefreshControl) {
        self.btcWalletService.getTransactions({ (result) in
            switch result {
            case .success(let transactions):
                self.transactions = transactions
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
                break
            case .failure(let error):
                if case .internalError(let message, _ ) = error {
                    let localizedErrorMessage = NSLocalizedString(message, comment: "TransactionList: 'Transactions not found' message.")
                    self.dialogService.showWarning(withMessage: localizedErrorMessage)
                } else {
                    self.dialogService.showError(withMessage: String.adamantLocalized.transactionList.notFound, error: error)
                }
                break
            }
            DispatchQueue.main.async {
                self.refreshControl.endRefreshing()
            }
        })
    }
    
    
    // MARK: - UITableView
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return transactions.count
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let transaction = transactions[indexPath.row]
        
        guard let controller = router.get(scene: AdamantScene.Wallets.Bitcoin.transactionDetails) as? BtcTransactionDetailsViewController else {
            return
        }

        controller.transaction = transaction
        controller.service = btcWalletService

        if let address = btcWalletService.wallet?.address {
            if transaction.senderAddress.caseInsensitiveCompare(address) == .orderedSame {
                controller.senderName = String.adamantLocalized.transactionDetails.yourAddress
            } else if transaction.recipientAddress.caseInsensitiveCompare(address) == .orderedSame {
                controller.recipientName = String.adamantLocalized.transactionDetails.yourAddress
            }
        }

        navigationController?.pushViewController(controller, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierCompact, for: indexPath) as? TransactionTableViewCell else {
            // TODO: Display & Log error
            return UITableViewCell(style: .default, reuseIdentifier: "cell")
        }
        
        let transaction = transactions[indexPath.row]
        
        cell.accessoryType = .disclosureIndicator
        
        configureCell(cell, for: transaction)
        return cell
    }
    
    func configureCell(_ cell: TransactionTableViewCell, for transaction: Payment) {
        let outgoing = transaction.isOutgoing
        let partnerId = outgoing ? transaction.recipientAddress : transaction.senderAddress
        
        configureCell(cell,
                      isOutgoing: outgoing,
                      partnerId: partnerId,
                      partnerName: nil,
                      amount: transaction.amountValue,
                      date: transaction.dateValue)
    }
}

extension Payment: TransactionDetails {
    var txId: String {
        return txid
    }
    
    var dateValue: Date? {
        if timestamp > 0 {
            return Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
        return nil
    }
    
    var amountValue: Decimal {
        return Decimal(self.amount) / Decimal(100000000)
    }
    
    var feeValue: Decimal? {
        if let fee = self.fee {
            return Decimal(fee) / Decimal(100000000)
        }
        return nil
    }
    
    var confirmationsValue: String? {
        if confirmations > 0 {
            return "\(confirmations)"
        }
        return nil
    }
    
    var blockValue: String? {
        if blockHeight > 0 {
            return "\(blockHeight)"
        }
        return nil
    }
    
    var isOutgoing: Bool {
        return state == .sent
    }
    
    var transactionStatus: TransactionStatus? {
        if self.confirmations > 0 {
            return .success
        } else {
            return .pending
        }
    }
    
    var senderAddress: String {
        return self.from.base58
    }
    
    var recipientAddress: String {
        return self.to.base58
    }
}
