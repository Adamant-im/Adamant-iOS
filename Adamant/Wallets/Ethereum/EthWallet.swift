//
//  EthWallet.swift
//  Adamant
//
//  Created by Anokhov Pavel on 03.08.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation
import web3swift

class EthWallet: WalletAccount {
	let address: String
	let ethAddress: EthereumAddress
	
	var balance: Decimal = 0
	var notifications: Int = 0
	
	init(address: String, ethAddress: EthereumAddress) {
		self.address = address
		self.ethAddress = ethAddress
	}
}
