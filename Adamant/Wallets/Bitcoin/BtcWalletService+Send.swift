//
//  BtcWalletService+Send.swift
//  Adamant
//
//  Created by Anton Boyarkin on 08/02/2019.
//  Copyright © 2019 Adamant. All rights reserved.
//

import UIKit
import BitcoinKit
import BitcoinKit.Private

extension BitcoinKit.Transaction: RawTransaction {
    var txHash: String? {
        return txID
    }
}

extension BtcWalletService: WalletServiceTwoStepSend {
    typealias T = BitcoinKit.Transaction
    
    func transferViewController() -> UIViewController {
        guard let vc = router.get(scene: AdamantScene.Wallets.Bitcoin.transfer) as? BtcTransferViewController else {
            fatalError("Can't get BtcTransferViewController")
        }
        
        vc.service = self
        return vc
    }
    
    
    // MARK: Create & Send
    func createTransaction(recipient: String, amount: Decimal, completion: @escaping (WalletServiceResult<BitcoinKit.Transaction>) -> Void) {
        // MARK: 1. Prepare
        guard let wallet = self.btcWallet else {
            completion(.failure(error: .notLogged))
            return
        }
        
        let changeAddress = wallet.publicKey.toCashaddr()
        let key = wallet.privateKey
        
        guard let toAddress = try? AddressFactory.create(recipient) else {
            completion(.failure(error: .accountNotFound))
            return
        }
        
        let rawAwount = NSDecimalNumber(decimal: amount * Decimal(100_000_000)).int64Value
        
        // MARK: Go background
        defaultDispatchQueue.async {
            
            let latestBlockHeight = (try? self.blockStore?.latestBlockHeight() ?? 0) ?? 0
            // MARK: 2. Search for unspent transactions
            let payments = self.getUnspentTransactions()
            var utxos: [UnspentTransaction] = []
            for p in payments {
                let value = p.amount
                let lockScript = Script.buildPublicKeyHashOut(pubKeyHash: p.to.data)
                let txHash = Data(hex: p.txid).map { Data($0.reversed()) } ?? Data()
                let txIndex = UInt32(p.index)
                print(p.txid, txIndex, lockScript.hex, value)
                
                let unspentOutput = TransactionOutput(value: UInt64(value), lockingScript: lockScript)
                let unspentOutpoint = TransactionOutPoint(hash: txHash, index: txIndex)
                let utxo = UnspentTransaction(output: unspentOutput, outpoint: unspentOutpoint)
                utxos.append(utxo)
            }
            
            // MARK: 3. Create local transaction
            let transaction = BitcoinKit.Transaction.createNewTransaction(toAddress: toAddress, amount: UInt64(rawAwount), fee: UInt64(BtcWalletService.defaultFee), changeAddress: changeAddress, utxos: utxos, lockTime: UInt32(latestBlockHeight+1), keys: [key])
            completion(.success(result: transaction))
        }
    }
    
    func sendTransaction(_ transaction: BitcoinKit.Transaction, completion: @escaping (WalletServiceResult<String>) -> Void) {
        defaultDispatchQueue.async {
            completion(.success(result: transaction.txID))
            self.peerGroup?.sendTransaction(transaction: transaction)
        }
    }
    
    func getUnspentTransactions() -> [Payment] {
        guard let address = self.btcWallet?.publicKey.toCashaddr() else {
            return []
        }
        
        return try! blockStore?.unspentTransactions(address: address) ?? []
    }
}

extension BitcoinKit.Transaction: TransactionDetails {
    var txId: String {
        return txID
    }
    
    var dateValue: Date? {
        //      0               Not locked
        //      < 500000000     Block number at which this transaction is unlocked
        //      >= 500000000    UNIX timestamp at which this transaction is unlocked
        switch lockTime {
        case 1..<500000000:
//            if let timestamp = timestamp {
//                return Date(timeIntervalSince1970: TimeInterval(timestamp))
//            } else {
                return nil
//            }
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
//        if let fee = self.fee {
//            return Decimal(fee) / Decimal(100000000)
//        }
        return nil
    }
    
    var confirmationsValue: String? {
        return "0"
    }
    
    var blockValue: String? {
        switch lockTime {
        case 1..<500000000:
            return "\(lockTime)"
        default:
            return nil
        }
    }
    
    var isOutgoing: Bool {
        return true
    }
    
    var transactionStatus: TransactionStatus? {
        return .pending
    }
    
    var senderAddress: String {
        return ""//self.from.base58
    }
    
    var recipientAddress: String {
        return ""//self.to.base58
    }
}

public protocol BinaryConvertible {
    static func +(lhs: Data, rhs: Self) -> Data
    static func +=(lhs: inout Data, rhs: Self)
}

public extension BinaryConvertible {
    public static func +(lhs: Data, rhs: Self) -> Data {
        var value = rhs
        let data = Data(buffer: UnsafeBufferPointer(start: &value, count: 1))
        return lhs + data
    }
    
    public static func +=(lhs: inout Data, rhs: Self) {
        lhs = lhs + rhs
    }
}

extension UInt8 : BinaryConvertible {}
extension UInt16 : BinaryConvertible {}
extension UInt32 : BinaryConvertible {}
extension UInt64 : BinaryConvertible {}
extension Int8 : BinaryConvertible {}
extension Int16 : BinaryConvertible {}
extension Int32 : BinaryConvertible {}
extension Int64 : BinaryConvertible {}
extension Int : BinaryConvertible {}

extension Bool : BinaryConvertible {
    public static func +(lhs: Data, rhs: Bool) -> Data {
        return lhs + (rhs ? UInt8(0x01) : UInt8(0x00)).littleEndian
    }
}

extension String : BinaryConvertible {
    public static func +(lhs: Data, rhs: String) -> Data {
        guard let data = rhs.data(using: .ascii) else { return lhs}
        return lhs + data
    }
}

extension Data : BinaryConvertible {
    public static func +(lhs: Data, rhs: Data) -> Data {
        var data = Data()
        data.append(lhs)
        data.append(rhs)
        return data
    }
}

enum SignError: Error {
    case noPreviousOutput
    case noPreviousOutputAddress
    case noPrivateKey
}

enum SerializationError: Error {
    case noPreviousOutput
    case noPreviousTransaction
}
