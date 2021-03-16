//
//  OZUI.swift
//  Alamofire
//
//  Created by Igor Ovchinnikov on 19/08/2019.
//

import Foundation

class InfoLabel: UILabel {
    var textInsets = UIEdgeInsets.zero {
        didSet { invalidateIntrinsicContentSize() }
    }
    
    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let insetRect = bounds.inset(by: textInsets)
        let textRect = super.textRect(forBounds: insetRect, limitedToNumberOfLines: numberOfLines)
        let invertedInsets = UIEdgeInsets(top: -textInsets.top,
                                          left: -textInsets.left,
                                          bottom: -textInsets.bottom,
                                          right: -textInsets.right)
        return textRect.inset(by: invertedInsets)
    }
    
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }
}

extension UIAlertController {
    class func alert(title: String, message: String, okTitle: String, okAction: @escaping (() -> Void), cancelTitle: String, cancelAction: @escaping (() -> Void)) -> UIAlertController {
        let alertController = UIAlertController(title: title,
                                                message: message,
                                                preferredStyle: .alert)
        let okAction = UIAlertAction(title: okTitle,
                                     style: .default,
                                     handler: { (action) in
                                        okAction()
        })
        let cancelAction = UIAlertAction(title: cancelTitle,
                                         style: .cancel,
                                         handler: { (action) in
                                            cancelAction()
        })
        
        alertController.addAction(okAction)
        alertController.addAction(cancelAction)
        
        let dynamicColor : UIColor
//        if #available(iOS 13.0, *) {
//            dynamicColor = UIColor { (traitCollection: UITraitCollection) -> UIColor in
//                switch traitCollection.userInterfaceStyle {
//                case
//                .unspecified,
//                .light: return .black
//                case .dark: return .white
//                }
//            }
//        } else {
            dynamicColor = UIColor.black
//        }
//
//        alertController.view.tintColor = dynamicColor
        
        return alertController
    }
}
