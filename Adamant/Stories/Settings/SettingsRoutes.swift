//
//  SettingsRoutes.swift
//  Adamant
//
//  Created by Anokhov Pavel on 01.02.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit

extension AdamantScene {
	struct Settings {
		static let security = AdamantScene(identifier: "SecurityViewController") { r in
			let c = SecurityViewController()
			c.accountService = r.resolve(AccountService.self)
			c.dialogService = r.resolve(DialogService.self)
			c.notificationsService = r.resolve(NotificationsService.self)
			c.localAuth = r.resolve(LocalAuthentication.self)
			c.router = r.resolve(Router.self)
			return c
		}
        
        static let multiAccount = AdamantScene(identifier: "MultiAccountViewController") { r in
            let c = MultiAccountViewController()
            c.accountService = r.resolve(AccountService.self)
            c.notificationsService = r.resolve(NotificationsService.self)
            c.dialogService = r.resolve(DialogService.self)
            c.localAuth = r.resolve(LocalAuthentication.self)
            c.router = r.resolve(Router.self)
            return c
        }
        
        static let addAccount = AdamantScene(identifier: "AddAccountViewController", factory: { r in
            let c = AddAccountViewController()
            c.accountService = r.resolve(AccountService.self)
            c.notificationsService = r.resolve(NotificationsService.self)
            c.dialogService = r.resolve(DialogService.self)
            return c
        })
		
		static let qRGenerator = AdamantScene(identifier: "QRGeneratorViewController", factory: { r in
			let c = QRGeneratorViewController()
			c.dialogService = r.resolve(DialogService.self)
			return c
		})
		
		static let about = AdamantScene(identifier: "About") { r in
			let c = AboutViewController()
			c.accountService = r.resolve(AccountService.self)
			c.accountsProvider = r.resolve(AccountsProvider.self)
			c.dialogService = r.resolve(DialogService.self)
			c.router = r.resolve(Router.self)
			return c
		}
		
		private init() {}
	}
}
