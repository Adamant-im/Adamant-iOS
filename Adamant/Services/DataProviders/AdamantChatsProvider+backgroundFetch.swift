//
//  AdamantChatsProvider+backgroundFetch.swift
//  Adamant
//
//  Created by Anokhov Pavel on 13.03.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation

extension AdamantChatsProvider: BackgroundFetchService {
	func fetchBackgroundData(notificationsService: NotificationsService, completion: @escaping (FetchResult) -> Void) {
        let addressPool = securedStore.getCurrentAddressPool()
        
        for address in addressPool {
            if var account = securedStore.getAccount(by: address) {
                var lastHeight: Int64?
                if let raw = account.chatProvider.receivedLastHeight {
                    lastHeight = Int64(raw)
                } else {
                    lastHeight = nil
                }
                
                var notifiedCount = 0
                if let raw = account.chatProvider.notifiedLastHeight, let h = lastHeight {
                    let notifiedHeight = Int64(raw)
                    if h < notifiedHeight {
                        lastHeight = notifiedHeight
                        
                        if let count = account.chatProvider.notifiedCount {
                            notifiedCount = Int(count)
                        }
                    }
                }
                
                apiService.getMessageTransactions(address: address, height: lastHeight, offset: nil) { result in
                    switch result {
                    case .success(let transactions):
                        if transactions.count > 0 {
                            let total = transactions.count
                            account.chatProvider.notifiedCount = total + notifiedCount
                            
                            if let newLastHeight = transactions.map({$0.height}).sorted().last {
                                account.chatProvider.notifiedLastHeight = newLastHeight
                            }
                            
                            self.securedStore.updateAccount(account)
                            
                            notificationsService.showNotification(title: String.adamantLocalized.notifications.newMessageTitle, body: String.localizedStringWithFormat(String.adamantLocalized.notifications.newMessageBody, total + notifiedCount), type: .newMessages(count: total))
                            
                            completion(.newData)
                        } else {
                            completion(.noData)
                        }
                        
                    case .failure(_):
                        completion(.failed)
                    }
                }
            }
        }
	}
	
	func dropStateData() {
		securedStore.remove(StoreKey.chatProvider.notifiedLastHeight)
		securedStore.remove(StoreKey.chatProvider.notifiedMessagesCount)
	}
}
