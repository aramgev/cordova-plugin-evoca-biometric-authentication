//
//  UIColor+Hex.swift
//  TestApp
//
//  Created by Grigor Hakobyan on 3/23/20.
//

import UIKit

public extension UIColor {
    @nonobjc static func hex(_ value: UInt32) -> UIColor {
        let r = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((value & 0xFF00) >> 8) / 255.0
        let b = CGFloat((value & 0xFF)) / 255.0
        
        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}
