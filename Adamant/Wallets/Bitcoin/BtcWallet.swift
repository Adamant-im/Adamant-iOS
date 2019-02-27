//
//  BtcWallet.swift
//  Adamant
//
//  Created by Anton Boyarkin on 14/01/2019.
//  Copyright © 2019 Adamant. All rights reserved.
//

import Foundation
import BitcoinKit

class BtcWallet: WalletAccount {
    var address: String
    let privateKey: PrivateKey
    let publicKey: PublicKey
    
    var balance: Decimal = 0.0
    var notifications: Int = 0
    
    init(privateKey: PrivateKey) {
        self.privateKey = privateKey
        self.publicKey = privateKey.publicKey()
        self.address = publicKey.toCashaddr().base58
    }
}
