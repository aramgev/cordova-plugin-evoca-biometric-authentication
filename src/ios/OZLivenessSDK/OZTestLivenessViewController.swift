//
//  OZTestLivenessViewController.swift
//  OZLivenessSDK
//
//  Created by Igor Ovchinnikov on 19/08/2019.
//

import Foundation
import AVFoundation
import UIKit
import FirebaseMLVision
import DeviceKit

@available(iOS 11.0, *)
class OZTestLivenessViewController: OZFrameViewController {
    
    private let mp : CGFloat = 0.2
    private var _mlKitFPS : CGFloat = 0
    
    override var mlKitFPS: CGFloat {
        set {
            if _mlKitFPS == 0 {
                _mlKitFPS = newValue
            }
            else {
                _mlKitFPS = mp * _mlKitFPS + (1 - mp) * newValue
            }
        }
        get {
            return _mlKitFPS
        }
    }
    
    var refFrameView : OZFrameView?
    var sFrameView : OZFrameView?
    var lFrameView : OZFrameView?
    
    var leftInfoLabel: UILabel?
    var rightInfoLabel: UILabel?
    
    override func pInfoLabel() {
        let h : CGFloat = 100.0
        let offset : CGFloat = 16.0
        let leftInfoLabel = InfoLabel(frame: CGRect(
            x: offset,
            y: self.view.frame.height - h - offset,
            width: self.view.frame.width/2 - 3*offset/2,
            height: h
        ))
        leftInfoLabel.font = UIFont.systemFont(ofSize: 24.0)
        leftInfoLabel.numberOfLines = 0
        leftInfoLabel.textColor = UIColor.white
        leftInfoLabel.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        leftInfoLabel.textInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        leftInfoLabel.layer.cornerRadius = 15.0
        leftInfoLabel.layer.masksToBounds = true
        leftInfoLabel.textAlignment = .left
        leftInfoLabel.minimumScaleFactor = 0.5
        leftInfoLabel.adjustsFontSizeToFitWidth = true
        self.view.addSubview(leftInfoLabel)
        self.leftInfoLabel = leftInfoLabel
        
        self.leftInfoLabel?.text = ""
        
        let rightInfoLabel = InfoLabel(frame: CGRect(
            x: self.view.frame.width/2 + offset/2,
            y: self.view.frame.height - h - offset,
            width: self.view.frame.width/2 - 3*offset/2,
            height: h
        ))
        rightInfoLabel.font = UIFont.systemFont(ofSize: 24.0)
        rightInfoLabel.numberOfLines = 0
        rightInfoLabel.textColor = UIColor.white
        rightInfoLabel.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        rightInfoLabel.textInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        rightInfoLabel.layer.cornerRadius = 15.0
        rightInfoLabel.layer.masksToBounds = true
        rightInfoLabel.textAlignment = .right
        rightInfoLabel.minimumScaleFactor = 0.5
        rightInfoLabel.adjustsFontSizeToFitWidth = true
        self.view.addSubview(rightInfoLabel)
        self.rightInfoLabel = rightInfoLabel
        
        self.rightInfoLabel?.text = ""
    }
    
    override func pFrameView() {
        
        guard let videoPreviewLayer = videoPreviewLayer else { return }
        
        let lframeView = OZOvalView(frame: videoPreviewLayer.frame)
        lframeView.lineWidth = OZSDK.customization.ovalCustomization.strokeWidth
        lframeView.fillColor = UIColor.black.withAlphaComponent(0.4)
        lframeView.strokeColor = UIColor.gray
        
        let sframeView = OZOvalView(frame: videoPreviewLayer.frame)
        sframeView.lineWidth = OZSDK.customization.ovalCustomization.strokeWidth
        sframeView.fillColor = UIColor.black.withAlphaComponent(0.3)
        sframeView.strokeColor = UIColor.gray
        
        refFrameView = OZFrameView(frame: videoPreviewLayer.frame)
        refFrameView?.lineWidth = OZSDK.customization.ovalCustomization.strokeWidth
        refFrameView?.fillColor = UIColor.black.withAlphaComponent(0.3)
        refFrameView?.strokeColor = UIColor.white
        refFrameView?.frameSize = nFaceFrame
        
        let cHMax = nFaceFrame.height + сThreshold * faceProportion * self.view.frame.width
        let cHMin = nFaceFrame.height - сThreshold * faceProportion * self.view.frame.width
        
        let minH = cHMin - hThreshold * cHMin
        let maxH = cHMax + hThreshold * cHMax
        
        let relativeError = hThreshold
        let absoluteError = hThreshold * videoPreviewLayer.frame.height
        
        sframeView.frameSize = CGSize(
            width:  (nFaceFrame.height - absoluteError) / faceProportion,
            height: nFaceFrame.height - absoluteError
        )
        
        lframeView.frameSize = CGSize(
            width:  (nFaceFrame.height + absoluteError) / faceProportion,
            height: nFaceFrame.height + absoluteError
        )
        
        self.sFrameView = sframeView
        self.lFrameView = lframeView
        
        let cSize = CGSize(
            width:  2 * сThreshold * videoPreviewLayer.frame.width,
            height: 2 * сThreshold * videoPreviewLayer.frame.height
        )
        
        let cframeView = OZFrameView(frame: CGRect(
            x: videoPreviewLayer.frame.origin.x + videoPreviewLayer.frame.width / 2 - cSize.width / 2,
            y: videoPreviewLayer.frame.origin.y + videoPreviewLayer.frame.height / 2 - cSize.height / 2,
            width: cSize.width,
            height: cSize.height)
        )
        cframeView.fillRule = .nonZero
        cframeView.lineWidth = OZSDK.customization.ovalCustomization.strokeWidth
        cframeView.fillColor = UIColor.gray.withAlphaComponent(0.3)
        cframeView.strokeColor = UIColor.gray.withAlphaComponent(0.3)
        cframeView.frameSize = cSize
        
        self.frameView = OZTestFrameView(frame: videoPreviewLayer.frame)
        self.frameView?.lineWidth = OZSDK.customization.ovalCustomization.strokeWidth
        self.frameView?.fillColor = UIColor.clear
        self.frameView?.strokeColor = UIColor.clear
        
        self.view.addSubview(cframeView)
        self.view.addSubview(sframeView)
        self.view.addSubview(lframeView)
        self.view.addSubview(self.frameView!)
        self.view.layoutSubviews()
    }
    
    private var firstProccessTimestamp : Date?
    private var processCount = 0
    
    override func process(faces: [VisionFace], completion: @escaping (() -> Void)) {
        if firstProccessTimestamp == nil {
            firstProccessTimestamp = Date()
        }
        processCount += 1
        if  let face = faces.first,
            let ovalViewPosition = refFrameView?.framePosition,
            let ovalViewSize = refFrameView?.frameSize,
            let sFrameView = sFrameView, let lFrameView = lFrameView,
            let videoPreviewLayer = self.videoPreviewLayer {
            
            
            let frame = face.frame
            let scale = videoPreviewLayer.bounds.height / self.captureImageSize.width
            
            let faceSize = CGSize(width:    frame.size.height   * scale * mlKitScale,
                                  height:   frame.size.width    * scale * mlKitScale)
            let facePosition = CGPoint(x: frame.origin.y * scale - faceSize.width   * (mlKitScale-1) / 2,
                                       y: frame.origin.x * scale - faceSize.height  * (mlKitScale-1) / 2)
            
            sFrameView.framePosition = CGPoint(
                x: facePosition.x + faceSize.width/2 - sFrameView.currentPathFrame.width/2,
                y: facePosition.y + faceSize.height/2 - sFrameView.currentPathFrame.height/2
            )
            lFrameView.framePosition = CGPoint(
                x: facePosition.x + faceSize.width/2 - lFrameView.currentPathFrame.width/2,
                y: facePosition.y + faceSize.height/2 - lFrameView.currentPathFrame.height/2
            )
            
            self.frameView?.frameSize = CGSize(
                width:  faceSize.height / faceProportion,
                height: faceSize.height
            )
            self.frameView?.framePosition = CGPoint(
                x: facePosition.x + (faceSize.width - faceSize.height / faceProportion) / 2,
                y: facePosition.y
            )
            
            let hDeviation = faceSize.height - ovalViewSize.height
            let dx = ((ovalViewPosition.x + ovalViewSize.width / 2) - (facePosition.x + faceSize.width / 2)) / videoPreviewLayer.frame.width
            let dy = ((ovalViewPosition.y + ovalViewSize.height / 2) - (facePosition.y + faceSize.height / 2)) / videoPreviewLayer.frame.height
            
            
            if abs(hDeviation) <= hThreshold * videoPreviewLayer.frame.height && abs(dx) <= сThreshold && abs(dy) <= сThreshold {
                self.frameView?.strokeColor = OZSDK.customization.ovalCustomization.successStrokeColor
            }
            else {
                self.frameView?.strokeColor = OZSDK.customization.ovalCustomization.failStrokeColor
            }
            
            leftInfoLabel?.text = """
            👱‍♂️   h : \((faceSize.height/ovalViewSize.height).p())
            🙂   p : \(face.smilingProbability.p())
            👁 l p : \(face.leftEyeOpenProbability.p())
            👁 r p : \(face.rightEyeOpenProbability.p())
            """
            
        }
        else {
            self.frameView?.strokeColor = UIColor.clear
        }
        let fps : CGFloat
        if let ti = firstProccessTimestamp?.timeIntervalSinceNow, ti != 0 {
            fps = CGFloat(processCount)/CGFloat(-ti)
        }
        else {
            fps = 0
        }
        
        rightInfoLabel?.text = """
        ML FPS
        \(mlKitFPS.p())
        FACT MDL FPS
        \(fps.p())
        """
        completion()
    }
}

private extension CGFloat {
    func p() -> String {
        return String(format: "%.02f", self)
    }
}
