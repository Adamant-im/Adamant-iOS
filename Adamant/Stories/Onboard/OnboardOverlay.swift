//
//  OnboardOverlay.swift
//  Adamant
//
//  Created by Anton Boyarkin on 23/11/2019.
//  Copyright © 2019 Adamant. All rights reserved.
//

import UIKit

class OnboardOverlay: SwiftyOnboardOverlay {
    
    lazy var agreeSwitch: UISwitch = {
        let view = UISwitch()
        view.isOn = false
        return view
    }()
    
    lazy var agreeLabel: UILabel = {
        let view = UILabel()
        view.text = "  I accept"
        view.font = UIFont.adamantPrimary(ofSize: 16)//UIFont(name: "Exo2-Regular", size: 18)
        view.textColor = UIColor.black
        return view
    }()
    
    lazy var eulaButton: UIButton = {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .center
        
        let attrs = NSAttributedString(string: "Terms of Service",
                       attributes:
            [NSAttributedString.Key.foregroundColor: UIColor.black,
         NSAttributedString.Key.font: UIFont(name: "Exo2-Regular", size: 16) ?? UIFont.adamantPrimary(ofSize: 16),
         NSAttributedString.Key.underlineColor: UIColor.black,
         NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue])

        button.setAttributedTitle(attrs, for: .normal)
        return button
    }()
    
    func configure() {
        let margin = self.layoutMarginsGuide
        
        let stack = UIStackView(arrangedSubviews: [agreeSwitch, agreeLabel, eulaButton])
        stack.alignment = .fill
        stack.distribution = .fill
        stack.spacing = 4
        
        self.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.heightAnchor.constraint(equalTo: agreeSwitch.heightAnchor).isActive = true
        stack.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -20).isActive = true
        stack.centerXAnchor.constraint(equalTo: margin.centerXAnchor).isActive = true
    }
    
}
