//
//  ChatsRoutes.swift
//  Adamant
//
//  Created by Anokhov Pavel on 12.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit

extension AdamantScene {
	struct Chats {
		static let chatList = AdamantScene(identifier: "ChatListViewController", factory: { r in
			let c = ChatListViewController(nibName: "ChatListViewController", bundle: nil)
			c.accountService = r.resolve(AccountService.self)
			c.chatsProvider = r.resolve(ChatsProvider.self)
			c.transfersProvider = r.resolve(TransfersProvider.self)
			c.router = r.resolve(Router.self)
			c.notificationsService = r.resolve(NotificationsService.self)
			c.dialogService = r.resolve(DialogService.self)
			return c
		})
		
		static let chat = AdamantScene(identifier: "ChatViewController", factory: { r in
			let c = ChatViewController()
            c.accountService = r.resolve(AccountService.self)
			c.chatsProvider = r.resolve(ChatsProvider.self)
			c.dialogService = r.resolve(DialogService.self)
			c.router = r.resolve(Router.self)
			return c
		})
		
		static let newChat = AdamantScene(identifier: "NewChatViewController", factory: { r in
			let c = NewChatViewController()
			c.dialogService = r.resolve(DialogService.self)
			c.accountService = r.resolve(AccountService.self)
			c.accountsProvider = r.resolve(AccountsProvider.self)
			
			let navigator = UINavigationController(rootViewController: c)
			
			return navigator
		})
		
		private init() {}
	}
}
