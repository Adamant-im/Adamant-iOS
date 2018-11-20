//
//  AccountHeaderView.swift
//  Adamant
//
//  Created by Anokhov Pavel on 29.06.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit

protocol AccountHeaderViewDelegate: class {
	func addressLabelTapped()
    func accountSwitchTapped()
}

class AccountHeaderView: UIView {
	
	// MARK: - IBOutlets
	@IBOutlet weak var avatarImageView: UIImageView!
	@IBOutlet weak var addressButton: UIButton!
	@IBOutlet weak var walletViewContainer: UIView!
    @IBOutlet weak var accountSwitchButton: UIButton!
    @IBOutlet weak var badgeView: UIView!
    @IBOutlet weak var badgeLabel: UILabel!
	
	weak var delegate: AccountHeaderViewDelegate?
    
    override func awakeFromNib() {
        badgeView.layer.cornerRadius = badgeView.bounds.height / 2
        
        self.accountSwitchButton.tintColor = UIColor.adamant.primary
        self.badgeView.backgroundColor = UIColor.adamant.primary
    }
    
    func setAccountsBadge(_ value: Int) {
        self.badgeView.isHidden = value <= 0
        self.badgeLabel.text = "\(value)"
    }
	
	@IBAction func addressButtonTapped(_ sender: Any) {
		delegate?.addressLabelTapped()
	}
    
    @IBAction func accountSwitchButtonTapped(_ sender: Any) {
        delegate?.accountSwitchTapped()
    }
}
