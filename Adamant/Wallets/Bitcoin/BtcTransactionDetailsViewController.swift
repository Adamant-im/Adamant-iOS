//
//  BtcTransactionDetailsViewController.swift
//  Adamant
//
//  Created by Anton Boyarkin on 05/02/2019.
//  Copyright © 2019 Adamant. All rights reserved.
//

import UIKit

class BtcTransactionDetailsViewController: TransactionDetailsViewControllerBase {
    // MARK: - Dependencies
    
    weak var service: BtcWalletService?
    
    // MARK: - Properties
    
    private let autoupdateInterval: TimeInterval = 5.0
    weak var timer: Timer?
    
    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refresh), for: UIControl.Event.valueChanged)
        return control
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        currencySymbol = BtcWalletService.currencySymbol
        
        super.viewDidLoad()
        
        if service != nil {
            tableView.refreshControl = refreshControl
        }
        
        if transaction != nil {
            startUpdate()
        }
    }
    
    deinit {
        stopUpdate()
    }
    
    // MARK: - Overrides
    
    override func explorerUrl(for transaction: TransactionDetails) -> URL? {
        let id = transaction.txId
        
        return  URL(string: "\(AdamantResources.bitcoinExplorerAddress)\(id)")
    }
    
    @objc func refresh() {
        guard let id = transaction?.txId, let service = service else {
            refreshControl.endRefreshing()
            return
        }
        
        service.getTransaction(by: id) { [weak self] result in
            switch result {
            case .success(let trs):
                self?.transaction = trs
                
                DispatchQueue.main.async {
                    self?.tableView.reloadData()
                    self?.refreshControl.endRefreshing()
                }
                
            case .failure(let error):
                self?.dialogService.showRichError(error: error)
                
                DispatchQueue.main.async {
                    self?.refreshControl.endRefreshing()
                }
            }
        }
    }
    
    // MARK: - Autoupdate
    
    func startUpdate() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: autoupdateInterval, repeats: true) { [weak self] _ in
            guard let id = self?.transaction?.txId, let service = self?.service else {
                return
            }
            
            service.getTransaction(by: id) { result in
                switch result {
                case .success(let trs):
                    self?.transaction = trs
                    
                    DispatchQueue.main.async {
                        self?.tableView.reloadData()
                    }
                    
                case .failure:
                    break
                }
            }
        }
    }
    
    func stopUpdate() {
        timer?.invalidate()
    }
}
