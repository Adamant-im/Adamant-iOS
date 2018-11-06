//
//  AccountService.swift
//  Adamant
//
//  Created by Anokhov Pavel on 07.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation

// MARK: - Notifications
extension Notification.Name {
	struct AdamantAccountService {
		/// Raised when user has successfully logged in. See AdamantUserInfoKey.AccountService
		static let userLoggedIn = Notification.Name("adamant.accountService.userHasLoggedIn")
		
		/// Raised when user has logged out.
		static let userLoggedOut = Notification.Name("adamant.accountService.userHasLoggedOut")
		
		/// Raised when user is about to log out. Save your data.
		static let userWillLogOut = Notification.Name("adamant.accountService.userWillLogOut")
		
		/// Raised on account info (balance) updated.
		static let accountDataUpdated = Notification.Name("adamant.accountService.accountDataUpdated")
		
		/// Raised when user changed Stay In option.
		///
		/// UserInfo:
		/// - Adamant.AccountService.newStayInState with new state
		static let stayInChanged = Notification.Name("adamant.accountService.stayInChanged")
		
		
		/// Raised when wallets collection updated
		///
		/// UserInfo:
		/// - Adamant.AccountService.updatedWallet: wallet object
		/// - Adamant.AccountService.updatedWalletIndex: wallet index in AccountService.wallets collection
		static let walletUpdated = Notification.Name("adamant.accountService.walletUpdated")
		
		private init() {}
	}
}


// MARK: - Localization
extension String.adamantLocalized {
	struct accountService {
		static let updateAlertTitleV12 = NSLocalizedString("AccountService.update.v12.title", comment: "AccountService: Alert title. Changes in version 1.2")
		static let updateAlertMessageV12 = NSLocalizedString("AccountService.update.v12.message", comment: "AccountService: Alert message. Changes in version 1.2, notify user that he needs to relogin to initiate eth & lsk wallets")
	}
}


/// - loggedAccountAddress: Newly logged account's address
extension AdamantUserInfoKey {
	struct AccountService {
		static let loggedAccountAddress = "adamant.accountService.loggedin.address"
		static let newStayInState = "adamant.accountService.stayIn"
		static let updatedWallet = "adamant.accountService.updatedWallet"
		static let updatedWalletIndex = "adamant.accountService.updatedWalletIndex"
		
		private init() {}
	}
}

// MARK: - Other const

/// - notLogged: Not logged, empty
/// - isLoggingIn: Is currently trying to log in
/// - loggedIn: Logged in and idling
/// - updating: Is logged in and updating account info
enum AccountServiceState {
	case notLogged, isLoggingIn, loggedIn, updating
}

enum AccountServiceResult {
	case success(account: AdamantAccount, alert: (title: String, message: String)?)
	case failure(AccountServiceError)
}

enum AccountSavingResult {
    case success(account: LocalAdamantAccount, alert: (title: String, message: String)?)
    case failure(AccountServiceError)
}

enum AccountServiceError: Error {
	case userNotLogged
	case invalidPassphrase
	case wrongPassphrase
	case apiError(error: ApiServiceError)
	case internalError(message: String, error: Error?)
	
	var localized: String {
		switch self {
		case .userNotLogged:
			return String.adamantLocalized.sharedErrors.userNotLogged
			
		case .invalidPassphrase:
			return NSLocalizedString("AccountServiceError.InvalidPassphrase", comment: "Login: user typed in invalid passphrase")
			
		case .wrongPassphrase:
			return NSLocalizedString("AccountServiceError.WrongPassphrase", comment: "Login: user typed in wrong passphrase")
		
		case .apiError(let error):
			return error.localized
		
		case .internalError(let message, _):
			return String.adamantLocalized.sharedErrors.internalError(message: message)
		}
	}
}

extension AccountServiceError: RichError {
	var message: String {
		return localized
	}
	
	var internalError: Error? {
		switch self {
		case .apiError(let error as Error?), .internalError(_, let error):
			return error
			
		default:
			return nil
		}
	}
	
	var level: ErrorLevel {
		switch self {
		case .wrongPassphrase, .userNotLogged, .invalidPassphrase:
			return .warning
			
		case .apiError(let error):
			switch error {
			case .accountNotFound, .notLogged, .networkError:
				return .warning
				
			case .serverError, .internalError:
				return .error
			}
			
		case .internalError:
			return .error
		}
	}
}


// MARK: - Protocol
protocol AccountService: class {
	// MARK: State
	
	var state: AccountServiceState { get }
	var account: AdamantAccount? { get }
	var keypair: Keypair? { get }
	
	
	// MARK: Wallets
	var wallets: [WalletService] { get }
	
	
	// MARK: Account functions
	
	/// Update logged account info
    func update()
    func update(_ completion: ((AccountServiceResult) -> Void)?)
	
	/// Create new account with passphrase.
	func createAccountWith(passphrase: String, completion: @escaping (AccountServiceResult) -> Void)
	
	/// Login into Adamant using passphrase.
	func loginWith(passphrase: String, completion: @escaping (AccountServiceResult) -> Void)
	
	
	/// Login into Adamant using previously logged account
	func loginWithStoredAccount(completion: @escaping (AccountServiceResult) -> Void)
	
	/// Logout
	func logout()
	
	
	// MARK: Stay in functions
	
	/// There is a stored account information in secured store
	var hasStayInAccount: Bool { get }
	
	/// Use TouchID or FaceID to log in
	var useBiometry: Bool { get set }
	
	
	/// Save account data and use pincode to login
	///
	/// - Parameters:
	///   - pin: pincode to login
	///   - completion: completion handler
	func setStayLoggedIn(pin: String, completion: @escaping (AccountServiceResult) -> Void)
    
    
    /// Add aditional account to currently logined
    func addAccount(name: String, passphrase: String, completion: @escaping (AccountSavingResult) -> Void)
    func getAccounts() -> [String : LocalAdamantAccount]
    func getMainAccount() -> LocalAdamantAccount?
    func getAdditionalAccounts() -> [String : LocalAdamantAccount]
    func removeAdditionalAccounts(address: String, completion: @escaping (AccountServiceResult) -> Void)
    func dropAdditionalAccounts()
    func switchToAccount(address: String, completion: @escaping (AccountServiceResult) -> Void)
	
	/// Remove stored data
	func dropSavedAccount()
	
	/// If we have stored data with pin, validate it. If no data saved, always returns false.
	func validatePin(_ pin: String) -> Bool
}
