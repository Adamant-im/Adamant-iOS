//
//  DogeWalletService+Send.swift
//  Adamant
//
//  Created by Anton Boyarkin on 12/03/2019.
//  Copyright © 2019 Adamant. All rights reserved.
//

import BitcoinKit
import BitcoinKit.Private
import Alamofire

extension BitcoinKit.Transaction: RawTransaction {
    var txHash: String? {
        return txID
    }
}

extension DogeWalletService: WalletServiceTwoStepSend {
    typealias T = BitcoinKit.Transaction
    
    func transferViewController() -> UIViewController {
        guard let vc = router.get(scene: AdamantScene.Wallets.Doge.transfer) as? DogeTransferViewController else {
            fatalError("Can't get DogeTransferViewController")
        }
        
        vc.service = self
        return vc
    }
    
    
    // MARK: Create & Send
    func createTransaction(recipient: String, amount: Decimal, completion: @escaping (WalletServiceResult<BitcoinKit.Transaction>) -> Void) {
        // MARK: 1. Prepare
        guard let wallet = self.dogeWallet else {
            completion(.failure(error: .notLogged))
            return
        }
        
        let changeAddress = wallet.publicKey.toCashaddr()
        let key = wallet.privateKey
        
        guard let toAddress = try? LegacyAddress(recipient, for: self.network) else {
            completion(.failure(error: .accountNotFound))
            return
        }
        
        let rawAmount = NSDecimalNumber(decimal: amount * DogeWalletService.multiplier).uint64Value
        let fee = NSDecimalNumber(decimal: self.transactionFee * DogeWalletService.multiplier).uint64Value
        
        // MARK: Go background
        defaultDispatchQueue.async {
            // MARK: 2. Search for unspent transactions
            self.getUnspentTransactions({ result in
                switch result {
                case .success(let utxos):
                    // MARK: 3. Create local transaction
                    let transaction = BitcoinKit.Transaction.createNewTransaction(toAddress: toAddress, amount: rawAmount, fee: fee, changeAddress: changeAddress, utxos: utxos, keys: [key])
                    completion(.success(result: transaction))
                    break
                case .failure:
                    completion(.failure(error: .notEnoughMoney))
                    break
                }
            })
        }
    }
    
    func sendTransaction(_ transaction: BitcoinKit.Transaction, completion: @escaping (WalletServiceResult<String>) -> Void) {
        guard let raw = AdamantResources.dogeServers.randomElement(), let url = URL(string: raw) else {
            fatalError("Failed to build DOGE endpoint URL")
        }
        
        // Headers
        let headers = [
            "Content-Type": "application/json"
        ]
        
        // Request url
        let endpoint = url.appendingPathComponent(DogeApiCommands.sendTransaction())
        
        defaultDispatchQueue.async {
            // MARK: Prepare params
            let txHex = transaction.serialized().hex
            
            let parameters: [String : Any] = [
                "rawtx": txHex
            ]
            
            // MARK: Sending request
            Alamofire.request(endpoint, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers).responseJSON(queue: self.defaultDispatchQueue) { response in
                
                switch response.result {
                case .success(let data):
                    
                    if let result = data as? [String: Any], let txid = result["txid"] as? String {
                        completion(.success(result: txid))
                    } else {
                        completion(.failure(error: .internalError(message: "DOGE Wallet: not valid response", error: nil)))
                    }
                    
                case .failure:
                    completion(.failure(error: .internalError(message: "DOGE Wallet: server not response", error: nil)))
                }
            }
        }
    }
}

extension BitcoinKit.Transaction: TransactionDetails {
    var txId: String {
        return txID
    }
    
    var dateValue: Date? {
        switch lockTime {
        case 1..<500000000:
            return nil
        case 500000000...:
            return Date(timeIntervalSince1970: TimeInterval(lockTime))
        default:
            return nil
        }
    }
    
    var amountValue: Decimal {
        return Decimal(outputs[0].value) / Decimal(100000000)
    }
    
    var feeValue: Decimal? {
        return nil
    }
    
    var confirmationsValue: String? {
        return "0"
    }
    
    var blockValue: String? {
        return nil
    }
    
    var isOutgoing: Bool {
        return true
    }
    
    var transactionStatus: TransactionStatus? {
        return .pending
    }
    
    var senderAddress: String {
        return ""
    }
    
    var recipientAddress: String {
        return ""
    }
}
