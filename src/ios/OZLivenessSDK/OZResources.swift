//
//  OZResources.swift
//  OZLivenessSDK
//
//  Created by Igor Ovchinnikov on 03/09/2019.
//

import Foundation

@available(iOS 11.0, *)
extension OZLocalizationCode {
    var string: String {
        switch self {
        case .ru:
            return "ru"
        case .en:
            return "en"
        case .hy:
            return "hy"
        }
    }
}

@available(iOS 11.0, *)
class OZResources {
    static var localizationCode: String? {
        return OZSDK.localizationCode?.string
    }
    
    private init() { }
    
    private static func bundle(key : String = "OZResourceBundle") -> Bundle {
        let path = Bundle(for: OZResources.self).path(forResource: key, ofType: "bundle")!
        return Bundle(path: path) ?? Bundle.main
    }
    
    static var closeButtonImageBl : UIImage? {
        return UIImage(named: "closebuttonBl", in: self.bundle(), compatibleWith: nil)
    }
    
    static var closeButtonImageWh : UIImage? {
        return UIImage(named: "closebuttonWh", in: self.bundle(), compatibleWith: nil)
    }
    
    static var logo : UIImage? {
        return UIImage(named: "logo", in: self.bundle(), compatibleWith: nil)
    }
    
    static func localized(key: String) -> String {
        var bundle = self.bundle(key: "OZLocalizationBundle")
        if let languageCode = localizationCode {
            if let path = bundle.path(forResource: languageCode, ofType: "lproj") {
                bundle = Bundle(path: path) ?? bundle
            }
        }
        
        return NSLocalizedString(key, tableName: "Localizable", bundle: bundle, comment: "")
    }
    
}

