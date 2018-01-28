//
//  GlobalConstants.swift
//  Adamant
//
//  Created by Anokhov Pavel on 10.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit

extension UIColor {
	static let adamantPrimary = UIColor(named: "Gray_main")!
	static let adamantSecondary = UIColor(named: "Gray_secondary")!
	static let adamantChatIcons = UIColor(named: "Icons")!
	
	static let adamantChatRecipientBackground = UIColor(named: "Chat_recipient")!
	static let adamantChatSenderBackground = UIColor(named: "Chat_sender")!
}

extension UIFont {
	static func adamantPrimary(size: CGFloat) -> UIFont {
		return UIFont(name: "Exo 2", size: size)!
	}
}

