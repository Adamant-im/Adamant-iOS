//
//  BtcWalletRoutes.swift
//  Adamant
//
//  Created by Anton Boyarkin on 14/01/2019.
//  Copyright © 2019 Adamant. All rights reserved.
//

import Foundation

extension AdamantScene.Wallets {
    struct Bitcoin {
        /// Wallet preview
        static let wallet = AdamantScene(identifier: "BtcWalletViewController") { r in
            let c = BtcWalletViewController(nibName: "WalletViewControllerBase", bundle: nil)
            c.dialogService = r.resolve(DialogService.self)
            return c
        }

        /// Send BTC tokens
        static let transfer = AdamantScene(identifier: "BtcTransferViewController") { r in
            let c = BtcTransferViewController()
            c.dialogService = r.resolve(DialogService.self)
            c.chatsProvider = r.resolve(ChatsProvider.self)
            c.accountService = r.resolve(AccountService.self)
            c.accountsProvider = r.resolve(AccountsProvider.self)
            c.router = r.resolve(Router.self)
            return c
        }

        /// List of BTC transactions
        static let transactionsList = AdamantScene(identifier: "BtcTransactionsViewController") { r in
            let c = BtcTransactionsViewController(nibName: "TransactionsListViewControllerBase", bundle: nil)
            c.dialogService = r.resolve(DialogService.self)
            c.router = r.resolve(Router.self)
            return c
        }

        /// BTC transaction details
        static let transactionDetails = AdamantScene(identifier: "TransactionDetailsViewControllerBase") { r in
            let c = BtcTransactionDetailsViewController()
            c.dialogService = r.resolve(DialogService.self)
            return c
        }
    }
}
