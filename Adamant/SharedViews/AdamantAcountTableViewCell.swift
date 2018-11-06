//
//  AdamantAcountTableViewCell.swift
//  Adamant
//
//  Created by Anton Boyarkin on 25/10/2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit
import Eureka
import FreakingSimpleRoundImageView

public final class AdamantAcountTableViewCell: Cell<LocalAdamantAccount>, CellType  {

    // MARK: IBOutlets
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var detailsLabel: UILabel!
    @IBOutlet var avatarImageView: RoundImageView!
    
    public override func update() {
        super.update()
        
        if let value = row.value {
            titleLabel.text = value.name
            detailsLabel.text = value.address
        } else {
            titleLabel.text = nil
            detailsLabel.text = nil
        }
        
        avatarImageView.image = ChatTableViewCell.defaultAvatar
        avatarImageView.tintColor = UIColor.adamant.primary
        avatarImageView.borderColor = UIColor.adamant.primary
        avatarImageView.borderWidth = 1
    }
}

public final class AdamantAcountRow: Row<AdamantAcountTableViewCell>, RowType {
    required public init(tag: String?) {
        super.init(tag: tag)
        // We set the cellProvider to load the .xib corresponding to our cell
        cellProvider = CellProvider<AdamantAcountTableViewCell>(nibName: "AdamantAcountTableViewCell")
    }
}
