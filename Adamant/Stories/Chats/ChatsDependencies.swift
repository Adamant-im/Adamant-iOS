//
//  ChatsDependencies.swift
//  Adamant-ios
//
//  Created by Anokhov Pavel on 12.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Swinject

extension Container {
	func registerAdamantChatsStory() {
		self.storyboardInitCompleted(ChatsListViewController.self) { r, c in
			c.accountService = r.resolve(AccountService.self)
			c.chatProvider = r.resolve(ChatDataProvider.self)
			c.cellFactory = r.resolve(CellFactory.self)
		}
	}
}
