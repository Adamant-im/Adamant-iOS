//
//  ApiService.swift
//  Adamant-ios
//
//  Created by Anokhov Pavel on 05.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation

protocol ApiService {
	func getAccount(byPassphrase passphrase: String, completionHandler: @escaping (Account?, AdamantError?) -> Void)
	func getAccount(byPublicKey publicKey: String, completionHandler: @escaping (Account?, AdamantError?) -> Void)
	
	func getPublicKey(byAddress address: String, completionHandler: @escaping (String?, AdamantError?) -> Void)
	func getPublicKey(byPassphrase passphrase: String, completionHandler: @escaping (String?, AdamantError?) -> Void)
	
	func getTransactions(forAccount: String, type: TransactionType, completionHandler: @escaping ([Transaction]?, AdamantError?) -> Void)
	
	func transferFunds(sender: String, recipient: String, amount: UInt, keypair: Keypair, completionHandler: @escaping (Bool, AdamantError?) -> Void)
}
