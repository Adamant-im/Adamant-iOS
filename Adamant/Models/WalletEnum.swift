//
//  Wallet.swift
//  Adamant
//
//  Created by Anokhov Pavel on 29.06.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit

enum WalletEnum {
	case adamant(balance: Decimal)
	case ethereum(balance: Decimal)
    case lisk(balance: Decimal)
	
	var enabled: Bool {
		switch self {
		case .adamant: return true
		case .ethereum: return true
        case .lisk: return true
		}
	}
}


// MARK: - Resources
extension WalletEnum {
	var currencyLogo: UIImage {
		switch self {
		case .adamant: return #imageLiteral(resourceName: "wallet_adm")
		case .ethereum: return #imageLiteral(resourceName: "wallet_eth")
        case .lisk: return #imageLiteral(resourceName: "wallet_lsk")
		}
	}
	
	var currencySymbol: String {
		switch self {
		case .adamant: return "ADM"
		case .ethereum: return "ETH"
        case .lisk: return "LSK"
		}
	}
}

// MARK: - Formatter
extension WalletEnum {
	static var currencyFormatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.roundingMode = .floor
		formatter.positiveFormat = "#.########"
		return formatter
	}()
	
	var formattedShort: String? {
		switch self {
		case .adamant(let balance):
			return WalletEnum.currencyFormatter.string(from: balance as NSNumber)!
			
        case .ethereum(let balance):
            return WalletEnum.currencyFormatter.string(from: balance as NSNumber)!
            
        case .lisk(let balance):
            return WalletEnum.currencyFormatter.string(from: balance as NSNumber)!
		}
	}
	
	var formattedFull: String? {
		switch self {
		case .adamant(let balance), .ethereum(let balance), .lisk(let balance):
            return "\(WalletEnum.currencyFormatter.string(from: balance as NSNumber)!) \(currencySymbol)"
		}
	}
}