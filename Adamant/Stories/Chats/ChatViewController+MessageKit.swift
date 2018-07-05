//
//  ChatViewController+MessageKit.swift
//  Adamant
//
//  Created by Anokhov Pavel on 24.03.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation
import MessageKit
import SafariServices
import Haring

// MARK: - MessagesDataSource
extension ChatViewController: MessagesDataSource {
	func currentSender() -> Sender {
		guard let account = account else {
			fatalError("No account")
		}
		return Sender(id: account.address, displayName: account.address)
	}
	
	func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
		guard let message = chatController?.object(at: IndexPath(row: indexPath.section, section: 0)) as? MessageType else {
			fatalError("Data not synced")
		}
		
		return message
	}
	
	func numberOfMessages(in messagesCollectionView: MessagesCollectionView) -> Int {
		if let objects = chatController?.fetchedObjects {
			return objects.count
		} else {
			return 0
		}
	}
	
	func cellBottomLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
		if message.sentDate == Date.adamantNullDate {
			return nil
		}
        
        if let message = message as? MessageTransaction, message.statusEnum == .failed {
            return nil
        }
		
		let humanizedTime = message.sentDate.humanizedTime()
		
		if let expire = humanizedTime.expireIn {
			if !cellsUpdating.contains(indexPath) {
				cellsUpdating.append(indexPath)
				
				let timer = Timer.scheduledTimer(withTimeInterval: expire + 1, repeats: false) { [weak self] timer in
					self?.messagesCollectionView.reloadItems(at: [indexPath])
					
					if let index = self?.cellsUpdating.index(of: indexPath) {
						self?.cellsUpdating.remove(at: index)
					}
					
					if let index = self?.cellUpdateTimers.index(of: timer) {
						self?.cellUpdateTimers.remove(at: index)
					}
				}
				
				cellUpdateTimers.append(timer)
			}
		}
		
		return NSAttributedString(string: humanizedTime.string, attributes: [NSAttributedStringKey.font: UIFont.preferredFont(forTextStyle: .caption2)])
	}
}


// MARK: - MessagesDisplayDelegate
extension ChatViewController: MessagesDisplayDelegate {
	func messageStyle(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageStyle {
		let corner: MessageStyle.TailCorner = isFromCurrentSender(message: message) ? .bottomRight : .bottomLeft
		return .bubbleTail(corner, .curved)
	}
	
	func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
		if isFromCurrentSender(message: message) {
            guard let transaction = message as? ChatTransaction else {
                return UIColor.adamantChatSenderBackground
            }
            
            switch transaction.statusEnum {
            case .failed:
                return UIColor.adamantFailChatBackground
				
			case .pending:
				return UIColor.adamantPendingChatBackground
				
            case .delivered:
                return UIColor.adamantChatSenderBackground
            }
		} else {
			return UIColor.adamantChatRecipientBackground
		}
	}
	
	func textColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
		return UIColor.darkText
	}
	
	func enabledDetectors(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> [DetectorType] {
		return [.url]
	}
    
    func configureAccessoryView(_ accessoryView: UIView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        guard let message = message as? MessageTransaction else {
            accessoryView.subviews.first?.removeFromSuperview()
            return
        }
        
        switch message.messageStatus {
        case .failed:
            let icon = UIImageView(frame: CGRect(x: -28, y: -10, width: 20, height: 20))
            icon.contentMode = .scaleAspectFit
            icon.backgroundColor = UIColor.clear
            icon.image = #imageLiteral(resourceName: "cross")
            accessoryView.addSubview(icon)
            return
        default:
            accessoryView.subviews.first?.removeFromSuperview()
            return
        }
    }
    
    func messageHeaderView(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageHeaderView {
        let header = messagesCollectionView.dequeueReusableHeaderView(MessageDateHeaderView.self, for: indexPath)
        
        header.dateLabel.text = message.sentDate.humanizedDay()
        return header
    }
    
    func shouldDisplayHeader(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> Bool {
        if message.sentDate == Date.adamantNullDate {
            return false
        }
        
        guard let dataSource = messagesCollectionView.messagesDataSource else {
			return false
		}
		
        if indexPath.section == 0 {
			return true
		}
		
        let previousSection = indexPath.section - 1
        let previousIndexPath = IndexPath(item: 0, section: previousSection)
        let previousMessage = dataSource.messageForItem(at: previousIndexPath, in: messagesCollectionView)
        let timeIntervalSinceLastMessage = message.sentDate.timeIntervalSince(previousMessage.sentDate)
        return timeIntervalSinceLastMessage >= messagesCollectionView.showsDateHeaderAfterTimeInterval
    }
}

extension ChatViewController: MessageCellDelegate {
	func didTapMessage(in cell: MessageCollectionViewCell) {
		guard let indexPath = messagesCollectionView.indexPath(for: cell),
			let message = messagesCollectionView.messagesDataSource?.messageForItem(at: indexPath, in: messagesCollectionView) else {
			return
		}
		
		switch message {
		case let transfer as TransferTransaction:
			// MARK: Show transfer details
			guard let vc = router.get(scene: AdamantScene.Transactions.transactionDetails) as? TransactionDetailsViewController else {
				fatalError("Can't get TransactionDetails scene")
			}
			
			vc.transaction = transfer
			
			if let nav = navigationController {
				nav.pushViewController(vc, animated: true)
			} else {
				present(vc, animated: true, completion: nil)
			}
			
		case let message as MessageTransaction:
			// MARK: Show Retry/Cancel action sheet
			guard message.messageStatus == .failed else {
				break
			}
			
			let retry = UIAlertAction(title: String.adamantLocalized.alert.retry, style: .default, handler: { [weak self] action in
				self?.chatsProvider.retrySendMessage(message) { result in
					switch result {
					case .success: break
						
					case .failure(let error):
						self?.dialogService.showRichError(error: error)
						
					case .invalidTransactionStatus(_):
						break
					}
				}
			})
			
			let cancelMessage = UIAlertAction(title: String.adamantLocalized.alert.delete, style: .default, handler: { [weak self] action in
				self?.chatsProvider.cancelMessage(message) { result in
					switch result {
					case .success:
						DispatchQueue.main.async {
							self?.messagesCollectionView.reloadDataAndKeepOffset()
						}
						
					case .invalidTransactionStatus(_):
						self?.dialogService.showWarning(withMessage: String.adamantLocalized.chat.cancelError)
						
					case .failure(let error):
						self?.dialogService.showRichError(error: error)
					}
				}
			})
			
			dialogService.showSystemActionSheet(title: String.adamantLocalized.alert.retryOrDeleteTitle, message: String.adamantLocalized.alert.retryOrDeleteBody, actions: [retry, cancelMessage])
			
		default:
			break
		}
	}
	
	func didSelectURL(_ url: URL) {
        if url.scheme == "adm" {
            if let address = url.host {
                self.startNewChat(with: address)
            }
        } else {
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = UIColor.adamantPrimary
            present(safari, animated: true, completion: nil)
        }
	}
}


// MARK: - MessagesLayoutDelegate
extension ChatViewController: MessagesLayoutDelegate {
	func heightForLocation(message: MessageType, at indexPath: IndexPath, with maxWidth: CGFloat, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
		return 50
	}
	
	func avatarSize(for: MessageType, at: IndexPath, in: MessagesCollectionView) -> CGSize {
		return .zero
	}
	
	func cellBottomLabelAlignment(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> LabelAlignment {
		if isFromCurrentSender(message: message) {
			return LabelAlignment.messageTrailing(UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 16))
		} else {
			return LabelAlignment.messageLeading(UIEdgeInsets(top: 2, left: 16, bottom: 0, right: 0))
		}
	}
}


// MARK: - MessageInputBarDelegate
extension ChatViewController: MessageInputBarDelegate {
	func messageInputBar(_ inputBar: MessageInputBar, didPressSendButtonWith text: String) {
		let message = AdamantMessage.text(text)
		let valid = chatsProvider.validateMessage(message)
		switch valid {
		case .isValid:
			break
			
		case .empty:
			return
			
		case .tooLong:
			dialogService.showToastMessage(valid.localized)
			return
		}
		
		guard text.count > 0, let partner = chatroom?.partner?.address else {
			// TODO show warning
			return
		}
		
		chatsProvider.sendMessage(.text(text), recipientId: partner, completion: { [weak self] result in
			switch result {
			case .success: break
				
			case .failure(let error):
				switch error {
				case .messageNotValid, .notEnoughtMoneyToSend:
					DispatchQueue.main.async {
						if inputBar.inputTextView.text.count == 0 {
							inputBar.inputTextView.text = text
						}
					}
				default:
					break
				}
				
				self?.dialogService.showRichError(error: error)
			}
		})
		
		inputBar.inputTextView.text = String()
	}
	
	func messageInputBar(_ inputBar: MessageInputBar, textViewTextDidChangeTo text: String) {
		if text.count > 0 {
			let fee = AdamantMessage.text(text).fee
			setEstimatedFee(fee)
		} else {
			setEstimatedFee(0)
		}
	}
}


// MARK: - MessageType
// MARK: MessageTransaction
extension MessageTransaction: MessageType {
	public var sender: Sender {
		let id = self.senderId!
		return Sender(id: id, displayName: id)
	}
	
	public var messageId: String {
		return self.transactionId!
	}
	
	public var sentDate: Date {
		return self.date! as Date
	}
	
	public var data: MessageData {
		guard var message = message else {
			return MessageData.text("")
		}
        
        let pat = "U([0-9]{6,20})"
        if let regex = try? NSRegularExpression(pattern: pat, options: []) {
            message = regex.stringByReplacingMatches(in: message,
                                                     options: [],
                                                     range: NSRange(location: 0, length: message.count),
                                                     withTemplate: "adm://U$1")
        }
		
		if isMarkdown {
			let parser = MarkdownParser(font: UIFont.adamantChatDefault)
			return MessageData.attributedText(parser.parse(message))
		} else {
			return MessageData.text(message)
		}
	}
    
    public var messageStatus: MessageStatus {
        return self.statusEnum
    }
}

// MARK: TransferTransaction
extension TransferTransaction: MessageType {
	public var sender: Sender {
		let id = self.senderId!
		return Sender(id: id, displayName: id)
	}
	
	public var messageId: String {
		return transactionId!
	}
	
	public var sentDate: Date {
		return date! as Date
	}
	
	public var data: MessageData {
		return MessageData.attributedText(AdamantFormattingTools.formatTransferTransaction(self))
	}
}
