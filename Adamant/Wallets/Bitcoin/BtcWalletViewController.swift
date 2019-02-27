//
//  BtcWalletViewController.swift
//  Adamant
//
//  Created by Anton Boyarkin on 14/01/2019.
//  Copyright © 2019 Adamant. All rights reserved.
//

import UIKit

extension String.adamantLocalized {
    static let bitcoin = NSLocalizedString("AccountTab.Wallets.bitcoin_wallet", comment: "Account tab: Bitcoin wallet")
    
    static let sendBtc = NSLocalizedString("AccountTab.Row.SendBtc", comment: "Account tab: 'Send BTC tokens' button")
}

class BtcWalletViewController: WalletViewControllerBase {
    // MARK: Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        walletTitleLabel.text = String.adamantLocalized.bitcoin
    }
    
    override func sendRowLocalizedLabel() -> String {
        return String.adamantLocalized.sendBtc
    }
    
    override func encodeForQr(address: String) -> String? {
        return "bitcoin:\(address)"
    }
}
