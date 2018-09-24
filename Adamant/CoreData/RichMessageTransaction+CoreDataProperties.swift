//
//  RichMessageTransaction+CoreDataProperties.swift
//  Adamant
//
//  Created by Anokhov Pavel on 24.09.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//
//

import Foundation
import CoreData


extension RichMessageTransaction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RichMessageTransaction> {
        return NSFetchRequest<RichMessageTransaction>(entityName: "RichMessageTransaction")
    }

    @NSManaged public var richContent: [String:String]?
    @NSManaged public var richType: String?

}
