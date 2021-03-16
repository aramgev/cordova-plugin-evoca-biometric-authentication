//
//  OZFrameView.swift
//  OZLiveness
//
//  Created by Igor Ovchinnikov on 17/07/2019.
//  Copyright © 2019 Igor Ovchinnikov. All rights reserved.
//

import Foundation
import UIKit

private struct FramePath {
    let backgroundLayerPath : CGPath
    let lineLayerPath : CGPath
}

class OZFrameView: UIView {
    
    
    let backgroundLayer = CAShapeLayer()
    let lineLayer       = CAShapeLayer()
    let imageLayer      = CALayer()
    
    private var animationStart      : TimeInterval = 0
    private var animationDuration   : TimeInterval = 0
    
    private var startFrame          : CGRect = .zero
    fileprivate var finalFrame      : CGRect {
        get {
            return CGRect(origin: CGPoint(x: (layer.bounds.width - frameSize.width)/2,
                                          y: (layer.bounds.height - frameSize.height)/2),
                          size: frameSize)
        }
    }
    
    var animated: Bool {
        get {
            return backgroundLayer.animationKeys()?.contains("sLCA") ?? false
        }
    }
    
    var currentPathFrame: CGRect {
        get {
            return finalFrame 
        }
    }
    
    var frameSize: CGSize = .zero {
        didSet {
            _framePosition = nil
            layoutSubviews()
        }
    }
    
    func cancelAllAnimations() {
        DispatchQueue.main.async {
            self.backgroundLayer.removeAllAnimations()
            self.lineLayer.removeAllAnimations()
        }
    }
    
    fileprivate var _framePosition : CGPoint? = nil
    
    var framePosition: CGPoint? {
        get { return _framePosition }
        set {
            _framePosition = newValue
            layoutSubviews()
        }
    }
    
    var strokeColor = UIColor.white {
        didSet { self.changeLayerColor() }
    }
    
    var lineWidth: CGFloat = 4 {
        didSet { layoutSubviews() }
    }
    
    var fillRule: CAShapeLayerFillRule = .evenOdd {
        didSet { changeLayerColor() }
    }
    
    var fillColor: UIColor = UIColor.black.withAlphaComponent(0.5) {
        didSet { layoutSubviews() }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.pLayers()
        imageLayer.opacity = 0
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    fileprivate func pLayers() {
        self.changeLayerColor()
        layer.addSublayer(backgroundLayer)
        layer.addSublayer(lineLayer)
//        layer.addSublayer(imageLayer)
    }
    
    fileprivate func changeLayerColor() {
        backgroundLayer.isOpaque = false
        backgroundLayer.fillColor = fillColor.cgColor
        backgroundLayer.fillRule = fillRule
        
        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.lineWidth = lineWidth
        lineLayer.strokeColor = strokeColor.cgColor
        
//        imageLayer.contents = UIImage(named: "face")?.cgImage
    }
    
//    func changeOpacity(showFace: Bool) {
//        imageLayer.opacity      = showFace ? 0.8    : 0
//        lineLayer.opacity       = showFace ? 0      : 1
//        backgroundLayer.opacity = showFace ? 0      : 1
//    }
    
    override func layoutSubviews() {
        backgroundLayer.frame = layer.bounds
        lineLayer.frame = layer.bounds
        let paths = self.pPaths()
        backgroundLayer.path = paths.backgroundLayerPath
        lineLayer.path = paths.lineLayerPath
        imageLayer.frame = paths.lineLayerPath.boundingBoxOfPath
    }
    
    func animate(finalSize: CGSize, duration: CFTimeInterval = 5.0) {
        
        _framePosition = nil
        
        let paths = pPaths(size: finalSize)
        
        let shapeLayerAnimation = CABasicAnimation(keyPath: #keyPath(CAShapeLayer.path))
        shapeLayerAnimation.fromValue = backgroundLayer.path
        shapeLayerAnimation.toValue = paths.backgroundLayerPath
        shapeLayerAnimation.duration = duration
        shapeLayerAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
        backgroundLayer.add(shapeLayerAnimation, forKey: "sLCA")
        
        let ovalLayerAnimation = CABasicAnimation(keyPath: #keyPath(CAShapeLayer.path))
        ovalLayerAnimation.fromValue = lineLayer.path
        ovalLayerAnimation.toValue = paths.lineLayerPath
        ovalLayerAnimation.duration = duration
        ovalLayerAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
        
        lineLayer.add(ovalLayerAnimation, forKey: "oLCA")
        
        startFrame = CGRect(origin: CGPoint(x: (layer.bounds.width - frameSize.width)/2,
                                            y: (layer.bounds.height - frameSize.height)/2),
                            size: frameSize)
        
        animationStart      = Date().timeIntervalSince1970
        animationDuration   = duration
        
        frameSize = finalSize
    }
    
    fileprivate func pPaths(size: CGSize? = nil) -> FramePath {
        let layerWidth = layer.bounds.width
        let layerHeight = layer.bounds.height
        let pathWidth = size != nil ? size!.width : frameSize.width
        let pathHeight = size != nil ? size!.height : frameSize.height
        var pathX = (layerWidth - pathWidth) / 2
        var pathY = (layerHeight - pathHeight) / 2
        if let position = framePosition {
            pathX = position.x
            pathY = position.y
        }
        else {
            _framePosition = CGPoint(x: pathX,
                                     y: pathY)
        }
        
        let pbath = self.pPath(
            x: pathX,
            y: pathY,
            width: pathWidth,
            height: pathHeight
        )
        
        let bgPath = UIBezierPath(rect: layer.bounds)
        bgPath.append(pbath)
        bgPath.close()
        
        let linePath = self.pPath(
            x: pathX - lineWidth/2,
            y: pathY - lineWidth/2,
            width: pathWidth + lineWidth/2,
            height: pathHeight + lineWidth/2
        )
        
        return FramePath(backgroundLayerPath: bgPath.cgPath,
                         lineLayerPath: linePath.cgPath)
    }
    
    fileprivate func pPath(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> UIBezierPath {
        return UIBezierPath(
            rect: CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
        )
    }
}

class OZTestFrameView: OZOvalView {
    let centerPointLayer = CAShapeLayer()
    
    fileprivate override func pLayers() {
        super.pLayers()
        layer.addSublayer(centerPointLayer)
    }
    
    fileprivate override func changeLayerColor() {
        super.changeLayerColor()
        centerPointLayer.lineWidth      = lineWidth
        centerPointLayer.strokeColor    = strokeColor.cgColor
        centerPointLayer.fillColor      = strokeColor.cgColor
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        centerPointLayer.frame = layer.bounds
        var x = layer.bounds.width / 2
        var y = layer.bounds.height / 2
        if let framePosition = framePosition {
            x = self.currentPathFrame.width/2    + framePosition.x - lineWidth/2
            y = self.currentPathFrame.height/2   + framePosition.y - lineWidth/2
        }
        let centerPath = UIBezierPath(
            ovalIn: CGRect(
                x: x,
                y: y,
                width: lineWidth,
                height: lineWidth
            )
        )
        self.centerPointLayer.path = centerPath.cgPath
    }
}

class OZOvalView: OZFrameView {
    
    override var currentPathFrame: CGRect {
        get {
            if let layer = self.lineLayer.presentation(), let path = layer.path  {
                return path.boundingBox
            }
            else { return finalFrame }
        }
    }
    
    fileprivate override func pPath(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> UIBezierPath {
        return UIBezierPath(
            ovalIn: CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
        )
    }
}
