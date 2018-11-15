//
//  AddAccountViewController.swift
//  Adamant
//
//  Created by Anton Boyarkin on 23/10/2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit
import Eureka
import AVFoundation
import Photos
import QRCodeReader
import EFQRCode

protocol AccountEditorDelegate: class {
    func accountDidAdded(_ account: LocalAdamantAccount)
}

class AddAccountViewController: FormViewController {
    // MARK: Rows & Sections
    private enum Sections {
        case passphrase
        
        var tag: String {
            switch self {
            case .passphrase: return "pps"
            }
        }
        
        var localized: String {
            switch self {
            case .passphrase:
                return NSLocalizedString("MultiAccount.Passphrase", comment: "MultiAccount: 'Passphrase' label")
            }
        }
    }
    
    private enum Rows {
        case name
        case passphrase
        case addButton
        
        var tag: String {
            switch self {
            case .name: return "nm"
            case .passphrase: return "pp"
            case .addButton: return "addbttn"
            }
        }
        
        var localized: String {
            switch self {
            case .name:
                return NSLocalizedString("MultiAccount.Name", comment: "MultiAccount: 'Name' field")
            case .passphrase:
                return String.adamantLocalized.qrGenerator.passphrasePlaceholder
                
            case .addButton:
                return NSLocalizedString("MultiAccount.AddButton", comment: "MultiAccount: 'Add' button")
            }
        }
    }
    
    // MARK: Dependencies
    var accountService: AccountService!
    var notificationsService: NotificationsService!
    var dialogService: DialogService!
    
    // MARK: - Properties
    weak var delegate: AccountEditorDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = String.adamantLocalized.multiAccount.newAccount

        // MARK: Passphrase section
        form +++ Section() {
            $0.tag = Sections.passphrase.tag
            
            $0.footer = { [weak self] in
                var footer = HeaderFooterView<UIView>(.callback {
                    let view = ButtonsStripeView.adamantConfigured()
                    view.stripe = [.qrCameraReader, .qrPhotoReader]
                    view.delegate = self
                    
                    return view
                })
                
                footer.height = { ButtonsStripeView.adamantDefaultHeight }
                
                return footer
                }()
            }
            
            <<< TextRow() {
                $0.tag = Rows.name.tag
                $0.placeholder = Rows.name.localized
                $0.keyboardReturnType = KeyboardReturnTypeConfiguration(nextKeyboardType: .next, defaultKeyboardType: .go)
            }
            
            // Passphrase row
            <<< PasswordRow() {
                $0.tag = Rows.passphrase.tag
                $0.placeholder = Rows.passphrase.localized
                $0.keyboardReturnType = KeyboardReturnTypeConfiguration(nextKeyboardType: .go, defaultKeyboardType: .go)
            }
            
            +++ Section()
            <<< ButtonRow() {
                $0.title = Rows.addButton.localized
                $0.tag = Rows.addButton.tag
                }.onCellSelection { [weak self] (cell, row) in
                    self?.addAccount()
                }.cellUpdate { (cell, row) in
                    cell.textLabel?.textColor = UIColor.adamant.primary
        }
    }
    
    func addAccount() {
        guard let row: PasswordRow = form.rowBy(tag: Rows.passphrase.tag),
            let passphrase = row.value?.lowercased(), // Lowercased!
            AdamantUtilities.validateAdamantPassphrase(passphrase: passphrase) else {
                dialogService.showToastMessage(String.adamantLocalized.qrGenerator.wrongPassphraseError)
                return
        }
        
        dialogService.showProgress(withMessage: "", userInteractionEnable: false)
        DispatchQueue.global().async {
            var name = ""
            
            if let row: TextRow = self.form.rowBy(tag: Rows.name.tag), let value = row.value {
                name = value
            }
            
            self.addAccount(name: name, passphrase: passphrase)
        }
    }

    func addAccount(name: String, passphrase: String) {
        accountService.addAccount(name: name, passphrase: passphrase) { (result) in
            DispatchQueue.main.async {
                self.dialogService.dismissProgress()
                
                switch result {
                case .success(let account, _):
                    if self.notificationsService.notificationsMode == .push, let token = self.notificationsService.savedToken, let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                        appDelegate.registerRemoteNotification(for: account, with: token)
                    }
                    self.delegate?.accountDidAdded(account)
                    self.dismiss(animated: true, completion: nil)
                    self.navigationController?.popViewController(animated: true)
                    break
                case .failure(let error):
                    self.dialogService.showRichError(error: error)
                }
                
            }
        }
    }
}

// MARK: - Button stripe
extension AddAccountViewController: ButtonsStripeViewDelegate {
    func buttonsStripe(_ stripe: ButtonsStripeView, didTapButton button: StripeButtonType) {
        switch button {
        case .qrCameraReader:
            loginWithQrFromCamera()
            
        case .qrPhotoReader:
            loginWithQrFromLibrary()
            
        default:
            break
        }
    }
    
    func loginWithQrFromCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            let reader = QRCodeReaderViewController.adamantQrCodeReader()
            reader.delegate = self
            present(reader, animated: true, completion: nil)
            
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] (granted: Bool) in
                if granted {
                    if Thread.isMainThread {
                        let reader = QRCodeReaderViewController.adamantQrCodeReader()
                        reader.delegate = self
                        self?.present(reader, animated: true, completion: nil)
                    } else {
                        DispatchQueue.main.async {
                            let reader = QRCodeReaderViewController.adamantQrCodeReader()
                            reader.delegate = self
                            self?.present(reader, animated: true, completion: nil)
                        }
                    }
                } else {
                    return
                }
            }
            
        case .restricted:
            let alert = UIAlertController(title: nil, message: String.adamantLocalized.login.cameraNotSupported, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String.adamantLocalized.alert.ok, style: .cancel, handler: nil))
            present(alert, animated: true, completion: nil)
            
        case .denied:
            dialogService.presentGoToSettingsAlert(title: nil, message: String.adamantLocalized.login.cameraNotAuthorized)
        }
    }
    
    func loginWithQrFromLibrary() {
        let presenter: () -> Void = { [weak self] in
            let picker = UIImagePickerController()
            picker.delegate = self
            picker.allowsEditing = false
            picker.sourceType = .photoLibrary
            self?.present(picker, animated: true, completion: nil)
        }
        
        if #available(iOS 11.0, *) {
            presenter()
        } else {
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized:
                presenter()
                
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization { status in
                    if status == .authorized {
                        presenter()
                    }
                }
                
            case .restricted, .denied:
                dialogService.presentGoToSettingsAlert(title: nil, message: String.adamantLocalized.login.photolibraryNotAuthorized)
            }
        }
    }
}

// MARK: - QRCodeReaderViewControllerDelegate
extension AddAccountViewController: QRCodeReaderViewControllerDelegate {
    func reader(_ reader: QRCodeReaderViewController, didScanResult result: QRCodeReaderResult) {
        guard AdamantUtilities.validateAdamantPassphrase(passphrase: result.value) else {
            dialogService.showWarning(withMessage: String.adamantLocalized.login.wrongQrError)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                reader.startScanning()
            }
            return
        }
        
        reader.dismiss(animated: true, completion: {
            if let row: PasswordRow = self.form.rowBy(tag: Rows.passphrase.tag) {
                row.value = result.value
            }
        })
    }
    
    func readerDidCancel(_ reader: QRCodeReaderViewController) {
        reader.dismiss(animated: true, completion: nil)
    }
}

// MARK: - UIImagePickerControllerDelegate
extension AddAccountViewController: UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        dismiss(animated: true, completion: nil)
        
        guard let image = info[.originalImage] as? UIImage else {
            return
        }
        
        if let cgImage = image.toCGImage(), let codes = EFQRCode.recognize(image: cgImage), codes.count > 0 {
            for aCode in codes {
                if AdamantUtilities.validateAdamantPassphrase(passphrase: aCode) {
                    if let row: PasswordRow = self.form.rowBy(tag: Rows.passphrase.tag) {
                        row.value = aCode
                    }
                    return
                }
            }
            
            dialogService.showWarning(withMessage: String.adamantLocalized.login.wrongQrError)
        } else {
            dialogService.showWarning(withMessage: String.adamantLocalized.login.noQrError)
        }
    }
}
