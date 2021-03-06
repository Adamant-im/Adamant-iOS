//
//  RichMessageTools.swift
//  Adamant
//
//  Created by Anokhov Pavel on 08/06/2019.
//  Copyright © 2019 Adamant. All rights reserved.
//

import Foundation

struct RichMessageTools {
    static func richContent(from data: Data) -> [String:String]? {
        guard let jsonRaw = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        
        switch jsonRaw {
            // Valid format
        case var json as [String:String]:
            if let key = json[RichContentKeys.type] {
                json[RichContentKeys.type] = key.lowercased()
            }
            
            return json
            
            // Broken format, try to fix it
        case var json as [String:Any]:
            if let key = json[RichContentKeys.type] as? String {
                json[RichContentKeys.type] = key.lowercased()
            }
            
            var fixedJson = [String:String]()
            
            let formatter = AdamantBalanceFormat.rawNumberDotFormatter
            formatter.decimalSeparator = "."
            
            for (key, raw) in json {
                if let value = raw as? String {
                    fixedJson[key] = value
                } else if let value = raw as? NSNumber, let amount = formatter.string(from: value) {
                    fixedJson[key] = amount
                } else {
                    fixedJson[key] = String(describing: raw)
                }
            }
            
            return fixedJson
            
        default:
            return nil
        }
    }
    
    private init() {}
}
