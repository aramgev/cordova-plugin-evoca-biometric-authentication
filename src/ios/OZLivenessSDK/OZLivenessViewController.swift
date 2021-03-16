//
//  OZUI.swift
//  OZLiveness
//
//  Created by Igor Ovchinnikov on 15/07/2019.
//  Copyright © 2019 Igor Ovchinnikov. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit
import FirebaseMLVision
import DeviceKit

private enum ActionStatus {
    case start, preparing, run, waiting, final, cancel
}

private struct ActionState {
    var status: ActionStatus = .start
    var isSuccess: Bool = true
    var outputURL: URL? = nil
    var tryCount = 0
    var isRecording: Bool = false {
        didSet {
            if isRecording {
                startRecordingTimestamp = Date()
            }
            else {
                startRecordingTimestamp = nil
            }
        }
    }
    var startRecordingTimestamp : Date? = nil
}

extension OZJournal {
    
}

// MARK: Liveness

@available(iOS 11.0, *)
class OZLivenessViewController: OZFrameViewController {
    
    private     let scenarioId  = UUID().uuidString
    fileprivate var actionId    = UUID().uuidString
    
    weak var delegate: OZVerificationDelegate?
    
    var actions: [OZVerificationMovement] = [] {
        didSet {
            _actions = actions
        }
    }
    
    private var _actions: [OZVerificationMovement] = [] {
        didSet {
            actionId = UUID().uuidString
        }
    }
    
    private var currentAction: OZVerificationMovement? {
        get { return _actions.first }
    }
    private var videos : [OZVerificationResult] = []
    
    // MARK: - AV Parameters
    
    private var actionState = ActionState()
    
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var sourceTime: CMTime?
    
    private var timer: Timer? = nil
    private var additionalTimer: Timer? = nil

    private let livenessTimeInterval = 5.0
    private let livenessAnimationTimeInterval = 0.2
    private let livenessSubTimeInterval = 5.0
    private let minVideoLength = 3.0
    private let livenessPreparingTimeInterval = 0.8
    
    private let livenessOffsetTimeInterval = 1.0
    
    private var commonTryCount = 0
    
    private let nonSmileThreshold       : CGFloat = OZSDK.thresholdSettings.startSmilingProbability
    private let nonClosedEyesThreshold  : CGFloat = OZSDK.thresholdSettings.startEyesOpenProbability
    private let centerYThreshold        : CGFloat = OZSDK.thresholdSettings.centerEulerAngleY
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.addJournalEntry(isAction: false, event: .livenessCheckStart)
        self.addJournalEntry(isAction: true, event: .actionStart)
    }
    
    // MARK: -
    
    func addJournalEntry(isAction: Bool, event: OZJournalEvent, context: OZJournalContext = [:]) {
        if isAction {
            OZJournal.sharedInstance.addEntry(event: event, context: context + actionContext, actionSessionId: actionId, scenarioSessionId: scenarioId)
        }
        else {
            OZJournal.sharedInstance.addEntry(event: event, context: context + scenarioContext, scenarioSessionId: scenarioId)
        }
    }
    
    var scenarioContext: OZJournalContext {
        get {
            return ["actions": actions.map({ (action) -> String in
                return action.code
            })]
        }
    }
    
    var actionContext: OZJournalContext {
        get {
            if let actionCode = currentAction?.code {
                var attemptCountContext: OZJournalContext = [:]
                if let commonCount = OZSDK.attemptSettings.commonCount {
                    attemptCountContext["remaining_common"] = commonCount - self.commonTryCount
                    attemptCountContext["common"] = commonCount
                }
                if let singleCount = OZSDK.attemptSettings.singleCount {
                    attemptCountContext["remaining_single"] = singleCount - self.actionState.tryCount
                    attemptCountContext["single"] = singleCount
                }
                let context = [
                    "current_action": actionCode,
                    "attempt_count": attemptCountContext
                    ] as [String : Any]
                return context + scenarioContext
            }
            return self.scenarioContext
        }
    }
    
    // MARK: - Timer
    
    private func setTimer() {
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(timeInterval: livenessTimeInterval + livenessOffsetTimeInterval,
                                          target: self,
                                          selector: #selector(completeAction),
                                          userInfo: nil,
                                          repeats: false)
    }
    
    private func setAdditionalTimer() {
        self.additionalTimer?.invalidate()
        self.additionalTimer = Timer.scheduledTimer(timeInterval: livenessTimeInterval,
                                                    target: self,
                                                    selector: #selector(setFinalState),
                                                    userInfo: nil,
                                                    repeats: false)
    }
    
    @objc private func setFinalState() {
        self.actionState.status = .final
        self._stopRecording {
            
        }
    }
    
    private func startAction() {
        self.addJournalEntry(isAction: true, event: .actionStart)
        self.runAction()
    }
    
    private func restartAction(_ restartReasonMessage: String = "") {
        self.addJournalEntry(isAction: true, event: .actionRestart, context: ["message" : restartReasonMessage])
        self.runAction()
    }
    
    private func runAction() {
        DispatchQueue.main.async {
            self.actionState.isSuccess = false
            self.actionState.status = .start
            self.pFrameView()
            self.pInfoLabel()
            self.pCloseButton()
            // TODO: поправить
            self.blockDetection = false
            self._firstFace = nil
        }
    }
    
    private func removeAllVideos() {
        for video in videos {
            if let url = video.videoURL {
                OZFileVideoManager.deleteFile(url: url)
            }
        }
    }
    
    private func finalAction() {
        if self.videos.count != self.actions.count {
            self.commonTryCount += 1
            self.actionState.tryCount += 1
            if let commonCount = OZSDK.attemptSettings.commonCount, commonTryCount > commonCount {
                let result = OZVerificationResult(status: .failedBecauseOfAttemptLimit,
                                                  movement: currentAction!,
                                                  videoURL: nil,
                                                  timestamp: Date())
                self.videos.append(result)
                self.closeAction("Common attempts exceeded", withDelegate: true) // ""Превышено общее число попыток""
            }
            else if let singleCount = OZSDK.attemptSettings.singleCount, self.actionState.tryCount > singleCount {
                let result = OZVerificationResult(status: .failedBecauseOfAttemptLimit,
                                                  movement: currentAction!,
                                                  videoURL: nil,
                                                  timestamp: Date())
                self.videos.append(result)
                self.closeAction("Exceeded the number of attempts for a single gesture", withDelegate: true) // "Превышено число попыток для отдельного жеста"
            }
            else {
                self.showAlert()
            }
        }
        else {
            self.closeAction("All actions completed", withDelegate: true) // "Жесты выполнены"
        }
    }
    
    private func invalidateTimers() {
        self.timer?.invalidate()
        self.additionalTimer?.invalidate()
        self.preparingTimer?.invalidate()
        self.timer = nil
        self.additionalTimer = nil
        self.preparingTimer = nil
    }
    
    @objc private func dismissAfterAllActions() {
        self.frameView?.cancelAllAnimations()
        self.invalidateTimers()
        self.actionState.status = .cancel
        if self.actionState.isRecording {
            self.stopRecording { [weak self] in
                self?.finalAction()
            }
        }
        else {
            self.finalAction()
        }
    }
    
    @objc private func completeAction() {
        self.completeAction("")
    }
    
    private func completeAction(_ reasonMessage: String = "") {
        self.invalidateTimers()
        self.frameView?.cancelAllAnimations()
        self.actionState.status = .cancel
        let actionId    = self.actionId
        let scenarioId  = self.scenarioId
        DispatchQueue.main.async { [weak self] in
            self?.addJournalEntry(isAction: true, event: .actionFinish, context: ["message": reasonMessage])
            guard let self = self, let currentAction = self.currentAction else { return }
            self.actionButton?.isHidden = false
            
            if self.actionState.isSuccess, let outputURL = self.actionState.outputURL {
                let result = OZVerificationResult(status: .userProcessedSuccessfully,
                                                  movement: currentAction,
                                                  videoURL: outputURL,
                                                  timestamp: Date())
                self.videos.insert(result, at: 0)
                
                if self._actions.count > 1 {
                    self._actions.remove(at: 0)
                    if self._actions.count > 0 {
                        self.startAction()
                    }
                    return
                }
                self.dismissAfterAllActions()
            }
            else {
                self.dismissAfterAllActions()
            }
        }
    }
    
    private func showAlert() {
        // TODO: Добавить удаление видео
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let alert = UIAlertController.alert(title:      OZResources.localized(key: "FailAttention.Alert.Title"),
                                                message:    OZResources.localized(key: "FailAttention.Alert.Message"),
                                                okTitle:    OZResources.localized(key: "FailAttention.Alert.OkTitle"),
                                                okAction: { [weak self] in
                self?.restartAction("Action restart after displaying alert") // "Повторная попытка, после отображения алерта"
                self?.actionState.status = .start
                },
                                                cancelTitle: OZResources.localized(key: "FailAttention.Alert.CancelTitle"),
                                                cancelAction: { [weak self] in
                self?.closeAction(sender: self?.closeButton)
            })
            self.present(alert, animated: true, completion: { })
        }
    }
    
    override func pFrameView() {
        guard let videoPreviewLayer = videoPreviewLayer, let currentAction = currentAction else { return }
        if self.frameView == nil || !view.subviews.contains(self.frameView!) {
            let ovalView = self.frameView ?? OZOvalView(frame: videoPreviewLayer.frame)
            ovalView.lineWidth = OZSDK.customization.ovalCustomization.strokeWidth
//            ovalView.fillColor = OZSDK.customization.frameCustomization.backgroundColor
            ovalView.strokeColor = OZSDK.customization.ovalCustomization.failStrokeColor
            if !view.subviews.contains(ovalView) {
                view.addSubview(ovalView)
            }
            self.frameView = ovalView
        }
        self.frameView?.alpha = 1
        self.frameView?.cancelAllAnimations()
        switch currentAction {
        case .far:
            self.frameView?.frameSize = nFaceFrame
        case .close:
            self.frameView?.frameSize = fFaceFrame
        case .smile, .eyes, .down, .up, .left, .right, .scanning:
            self.frameView?.frameSize = nFaceFrame
        }
//        self.frameView?.changeOpacity(showFace: true)
        self.frameView?.alpha = 1
        self.view.layoutSubviews()
    }
    
    override func pInfoLabel() {
        super.pInfoLabel()
        self.infoLabel?.text = FaceReplacementState.noface.text
    }
    
    private enum FaceReplacementState {
        case right, left, far, close, high, low, indirect, withoutIncline, noface, smile, closedEyes, fixRequired
        var text : String {
            switch self {
            case .right:
                return OZResources.localized(key: "FaceState.Right.Recommendation")
            case .left:
                return OZResources.localized(key: "FaceState.Left.Recommendation")
            case .high:
                return OZResources.localized(key: "FaceState.High.Recommendation")
            case .low:
                return OZResources.localized(key: "FaceState.Low.Recommendation")
            case .far:
                return OZResources.localized(key: "FaceState.Far.Recommendation")
            case .close:
                return OZResources.localized(key: "FaceState.Close.Recommendation")
            case .indirect:
                return OZResources.localized(key: "FaceState.Indirect.Recommendation")
            case .withoutIncline:
                return OZResources.localized(key: "FaceState.WithoutIncline.Recommendation")
            case .smile:
                return OZResources.localized(key: "FaceState.Smile.Recommendation")
            case .closedEyes:
                return OZResources.localized(key: "FaceState.ClosedEyes.Recommendation")
            case .noface:
                return OZResources.localized(key: "FaceState.Noface.Recommendation")
            case .fixRequired:
                return OZResources.localized(key: "FaceState.FixRequired.Recommendation")
            }
        }
    }
    
    private var startTimestamp: Date = Date()
    
    private func fullRestartAction(_ restartReasonMessage: String = "", completion: @escaping (() -> Void)) {
        self.invalidateTimers()
        self.frameView?.layer.removeAllAnimations()
        self.restartAction(restartReasonMessage)
        self.changeFaceReplacementState(state: .noface)
        self.scanningLabel.layer.removeAllAnimations()
        self.stopRecording { [weak self] in
            self?.actionState.status = .start
            completion()
        }
    }
    
    private func subProcess(faces: [VisionFace], completion: @escaping (() -> Void)) {
        if let face = faces.first, let ovalViewPosition = frameView?.currentPathFrame.origin, let ovalViewSize = frameView?.currentPathFrame.size, let currentAction = currentAction {
            switch currentAction {
            case .close, .far:
                if self.actionState.status == .run || self.actionState.status == .preparing, let firstFace = _firstFace {
                    let proportion = self.faceToFrameProportion(face: face)
                    let referenceProportion = self.faceToFrameProportion(face: firstFace)
                    if proportion < 0.8 && referenceProportion + 0.03 < proportion {
                        self.changeInfo(text: OZResources.localized(key: "Action.Close.EvenCloser"))
                    }
                    else if proportion > 1.2 && referenceProportion - 0.03 > proportion {
                        self.changeInfo(text: OZResources.localized(key: "Action.Close.EvenFurther"))
                    }
                }

                self.thresholdProcess(currentAction:    currentAction,
                                      face:             face,
                                      refFrameSize:     ovalViewSize,
                                      refFramePosition: ovalViewPosition,
                                      successHandler: { [weak self] in
                                        self?.faceDynamicProcess(face: face, completion: completion)
                                        completion()
                    }, completion: completion)
            case .smile, .eyes, .down, .up, .left, .right:
                if actionState.status == .start || actionState.status == .preparing {
                    self.thresholdProcess(currentAction:    currentAction,
                                          face:             face,
                                          refFrameSize:     ovalViewSize,
                                          refFramePosition: ovalViewPosition,
                                          successHandler: { [weak self] in
                                            self?.faceStaticProcess(action: currentAction, face: face, completion: completion)
                        }, completion: completion)
                }
                else {
                    self.faceStaticProcess(action: currentAction, face: face, completion: completion)
                }
                
            case .scanning:
                if actionState.status == .start || actionState.status == .preparing {
                    self.thresholdProcess(currentAction:    currentAction,
                                          face:             face,
                                          refFrameSize:     ovalViewSize,
                                          refFramePosition: ovalViewPosition,
                                          successHandler: { [weak self] in
                                            self?.faceScanning(face: face, completion: completion)
                        }, completion: completion)
                }
                else {
                    self.faceScanning(face: face, completion: completion)
                }
                
            }
        }
        else {
            self.changeFaceReplacementState(state: .noface)
            completion()
        }
    }
    
    private var faceoutCount = 0
    
    override func process(faces: [VisionFace], completion: @escaping (() -> Void)) {
        if faces.count > 1 {
            if !actionState.isSuccess {
                self.fullRestartAction("There are more than 1 face in the frame") { [weak self] in // "В кадре больше, чем 1 лицо"
                    completion()
                }
            }
            else {
                completion()
            }
            return
        }
        if faces.count > 0 {
            faceoutCount = 0
        }
        else {
            faceoutCount += 1
        }
        guard faceoutCount < 5 else {
            if actionState.status == .start || actionState.status == .run || actionState.status == .preparing {
                if !actionState.isSuccess {
                    self.fullRestartAction("Face left frame") { [weak self] in // "Лицо покинуло кадр"
                        completion()
                    }
                    return
                }
                else {
                    completion()
                    return
                }
            }
            else if actionState.status == .waiting || actionState.status == .final {
                self.fullRestartAction("Face left frame") { [weak self] in // "Лицо покинуло кадр"
                    completion()
                }
                return
            }
            else {
                completion()
                return
            }
        }
        guard let currentAction = currentAction else {
            completion()
            return
        }
        switch currentAction {
        case .far, .close:
            if (self.actionState.status == .run && self.frameView?.animated != true) || self.actionState.status == .start {
                self.subProcess(faces: faces, completion: completion)
                return
            }
        default:
            if self.actionState.status != .cancel {
                self.subProcess(faces: faces, completion: completion)
                return
            }
        }
        completion()
    }
    
    private var lastAttentionMessageTimestamp = Date()
    
    private func showAttentionMessage(replacementState: FaceReplacementState? = nil) {
        guard -self.lastAttentionMessageTimestamp.timeIntervalSinceNow > 0.5 else {
            return
        }
        
        self.lastAttentionMessageTimestamp = Date()
        
        self.preparingTimer?.invalidate()
        self.preparingTimer = nil
        
        if actionState.status == .preparing {
            actionState.status = .start
        }
        if self.actionState.status == .cancel {
            return
        }
        if self.actionState.status == .start || self.actionState.status == .preparing {
            actionButton?.isEnabled = false
            frameView?.strokeColor = OZSDK.customization.ovalCustomization.failStrokeColor
        }
        
        if let text = replacementState?.text, text.count > 0, self.actionState.status == .start || self.actionState.status == .preparing {
            changeInfo(text: text)
        }
    }
    
    private func getMLKitFrame(face: VisionFace, scale: CGFloat? = nil) -> CGRect {
        guard let videoPreviewLayer = videoPreviewLayer else {
            return .zero
        }
        let _scale = scale ?? mlKitScale
        let frame = face.frame
        let scale = videoPreviewLayer.bounds.height / self.captureImageSize.width
        
        let faceSize = CGSize(width:    frame.size.height   * scale * _scale,
                              height:   frame.size.width    * scale * _scale)
        let facePosition = CGPoint(x: frame.origin.y * scale - faceSize.width   * (_scale-1) / 2,
                                   y: frame.origin.x * scale - faceSize.height  * (_scale-1) / 2)
        return CGRect(origin: facePosition, size: faceSize)
    }
    
    private func isFullFaceInFrame(face: VisionFace) -> Bool {
        guard let videoPreviewLayer = videoPreviewLayer else {
            return false
        }
        let frame = self.getMLKitFrame(face: face, scale: 0.9)
        let _faceSize        = CGSize(
            width:  frame.size.height / faceProportion,
            height: frame.size.height
        )
        let _facePosition    =  CGPoint(
            x: frame.origin.x + (frame.size.width - frame.size.height / faceProportion) / 2,
            y: frame.origin.y
        )
        
        let ltFacePoint = CGPoint(x: _facePosition.x,                   y: _facePosition.y)
        let rtFacePoint = CGPoint(x: _facePosition.x + _faceSize.width, y: _facePosition.y)
        let rbFacePoint = CGPoint(x: _facePosition.x + _faceSize.width, y: _facePosition.y + _faceSize.height)
        let lbFacePoint = CGPoint(x: _facePosition.x,                   y: _facePosition.y + _faceSize.height)
        
        return  videoPreviewLayer.frame.contains(ltFacePoint) &&
                videoPreviewLayer.frame.contains(rtFacePoint) &&
                videoPreviewLayer.frame.contains(rbFacePoint) &&
                videoPreviewLayer.frame.contains(lbFacePoint)
    }
    
    private func faceToFrameProportion(face: VisionFace) -> CGFloat {
        guard let ovalSize = frameView?.frameSize else {
            return 0
        }
        let faceFrame = self.getMLKitFrame(face: face)
        let faceSize = CGSize(
            width:  faceFrame.size.height / faceProportion,
            height: faceFrame.size.height
        )
        
        return faceSize.width / ovalSize.width
        
    }
    
    private func thresholdProcess(currentAction: OZVerificationMovement, face: VisionFace, refFrameSize: CGSize, refFramePosition: CGPoint, successHandler: (() -> Void), completion: @escaping (() -> Void)) {
        guard let videoPreviewLayer = videoPreviewLayer else {
            return
        }
        let frame           = self.getMLKitFrame(face: face)
        let faceSize        = frame.size
        let facePosition    = frame.origin

        let hDeviation = faceSize.height - refFrameSize.height
        
        let dx = ((refFramePosition.x + refFrameSize.width / 2) - (facePosition.x + faceSize.width / 2)) / videoPreviewLayer.frame.width
        let dy = ((refFramePosition.y + refFrameSize.height / 2) - (facePosition.y + faceSize.height / 2)) / videoPreviewLayer.frame.height
        
        var condition = abs(hDeviation) <= hThreshold * videoPreviewLayer.frame.height  && abs(dx) <= сThreshold && abs(dy) <= сThreshold
        
        var nonSmile        = true
        var nonnonOpenEyes  = true
        var straight        = true
        var withoutIncline  = true
        var cuttedFace = !self.isFullFaceInFrame(face: face)
        
        condition = condition && !cuttedFace
        
        if condition, currentAction == .smile, actionState.status == .start || actionState.status == .preparing {
            nonSmile = face.hasSmilingProbability && (face.smilingProbability < nonSmileThreshold)
            condition = condition && nonSmile
        }
        
        if condition, actionState.status == .start || actionState.status == .preparing {
            straight = abs(face.headEulerAngleY) < centerYThreshold
            condition = condition && straight
        }
        
        if  condition,
            actionState.status == .start || actionState.status == .preparing,
            currentAction == .down || currentAction == .up,
            let noseLandMark = face.landmark(ofType: .noseBase) {
            
            withoutIncline =    self.dFaceProportion(face: face, noseLandmark: noseLandMark) >= downThreshold &&
                                self.uFaceProportion(face: face, noseLandmark: noseLandMark) >= highThreshold
            condition = condition && withoutIncline
        }
        
        if condition, actionState.status == .start || actionState.status == .preparing {
            nonnonOpenEyes =    face.hasLeftEyeOpenProbability &&
                                face.hasRightEyeOpenProbability &&
                
                min(face.leftEyeOpenProbability, face.rightEyeOpenProbability) > (1 - nonClosedEyesThreshold)
            condition = condition && nonnonOpenEyes
        }
        
        if condition {
            successHandler()
            return
        }
        else {
            var state: FaceReplacementState? = nil
            if hDeviation < -hThreshold * videoPreviewLayer.frame.height {
                state = .far
            }
            else if hDeviation > hThreshold * videoPreviewLayer.frame.height {
                state = .close
            }
            if abs(dx) > сThreshold || abs(dy) > сThreshold || cuttedFace {
                state = .noface
            }
            else if !straight {
                state = .indirect
            }
            else if !withoutIncline {
                state = .withoutIncline
            }
            else if !nonSmile {
                state = .smile
            }
            else if !nonnonOpenEyes {
                state = .closedEyes
            }
            self.changeFaceReplacementState(state: state)
        }
        completion()
    }
    
    private var preparingTimer : Timer?
    
    @objc private func setRunStatus() {
        self.frameView?.strokeColor = OZSDK.customization.ovalCustomization.successStrokeColor
        self.startAction(sender: nil)
    }
    
    private var _firstFace: VisionFace?
    
    private let successfulLivenessCheckText = OZResources.localized(key: "FinalWaitingLivenessCheck")
    
    private func faceDynamicProcess(face: VisionFace, completion: @escaping (() -> Void)) {
        if self.actionState.status == .start {
            self.frameView?.strokeColor = OZSDK.customization.ovalCustomization.successStrokeColor
            self.changeFaceReplacementState(state: FaceReplacementState.fixRequired)
            self.actionState.status = .preparing
            self.preparingTimer = Timer.scheduledTimer(timeInterval: livenessPreparingTimeInterval,
                                                       target: self,
                                                       selector: #selector(setRunStatus),
                                                       userInfo: nil,
                                                       repeats: false)
            _firstFace = face
        }
        else if self.actionState.status == .preparing {
            
        }
        else if self.actionState.status == .run {
            self.actionState.isSuccess = true
            self.changeInfo(text: successfulLivenessCheckText)
            self.closeButton?.isEnabled = false
            self.actionState.status = .waiting
            self.invalidateTimers()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?._stopRecording { [weak self] in
                    self?.completeAction("Action completed") // "Жест выполнен"
                    completion()
                    return
                }
            }
        }
    }
    
    private let scanningLabel : InfoLabel = {
        let scanningLabel = InfoLabel(frame: .zero)
        scanningLabel.font = UIFont.systemFont(ofSize: 24.0)
        scanningLabel.numberOfLines = 0
        scanningLabel.textColor = UIColor.white
        scanningLabel.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        scanningLabel.textInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        scanningLabel.layer.cornerRadius = 15.0
        scanningLabel.layer.masksToBounds = true
        scanningLabel.textAlignment = .right
        scanningLabel.minimumScaleFactor = 0.5
        scanningLabel.adjustsFontSizeToFitWidth = true
        
        scanningLabel.text = OZResources.localized(key: "Action.Scanning.Task")
        scanningLabel.textColor = UIColor.white
        scanningLabel.sizeToFit()
        return scanningLabel
    }()
    
    private var scanningState : ScanningState = .start
    
    private let flashView : UIView = {
        let view = UIView(frame: .zero)
        view.backgroundColor = UIColor.green
        return view
    }()
    
    private enum ScanningState {
        case start, run, complete
    }
    
    private func faceScanning(face: VisionFace, completion: @escaping (() -> Void)) {
        if self.actionState.status == .start {
            self.frameView?.strokeColor = OZSDK.customization.ovalCustomization.successStrokeColor
            self.changeFaceReplacementState(state: FaceReplacementState.fixRequired)
            self.actionState.status = .preparing
            self.preparingTimer = Timer.scheduledTimer(timeInterval: livenessPreparingTimeInterval,
                                                       target: self,
                                                       selector: #selector(setRunStatus),
                                                       userInfo: nil,
                                                       repeats: false)
            self.scanningState = .start
            completion()
            return
        }
        else if self.actionState.status == .preparing {
            completion()
            return
        }
        else if self.actionState.status == .run {
            if self.scanningState == .start {
                self.scanningState = .run
//                self.frameView?.alpha = 0
                self.changeInfo(text: "")
                
                scanningLabel.frame = CGRect(
                    x: self.view.frame.width/2 - self.scanningLabel.frame.width/2,
                    y: self.view.frame.height/2 - self.scanningLabel.frame.height/2,
                    width: self.scanningLabel.frame.width,
                    height: self.scanningLabel.frame.height
                )
                
                self.view.addSubview(scanningLabel)
                
                let animationTime = 3.8
                
                UIView.animate(withDuration: animationTime/3, animations: { [weak self] in
                    guard let self = self else { return }
                    self.scanningLabel.frame = CGRect(
                        x: self.view.frame.width/2 - self.scanningLabel.frame.width/2,
                        y: self.view.frame.height - self.scanningLabel.frame.height,
                        width: self.scanningLabel.frame.width,
                        height: self.scanningLabel.frame.height
                    )
                }) { [weak self] (isComplete) in
                    guard let self = self else { return }
                    self.flashView.frame = self.view.bounds
                    self.view.addSubview(self.flashView)
                    let lastBrightness = UIScreen.main.brightness
                    UIScreen.main.brightness = 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.flashView.removeFromSuperview()
                        UIScreen.main.brightness = lastBrightness
                    }
                    UIView.animate(withDuration: 2*animationTime/3, animations: { [weak self] in
                        guard let self = self else { return }
                        self.scanningLabel.frame = CGRect(
                            x: self.view.frame.width/2 - self.scanningLabel.frame.width/2,
                            y: 0,
                            width: self.scanningLabel.frame.width,
                            height: self.scanningLabel.frame.height
                        )
                    }) { [weak self]  (isComplete) in
                        guard let self = self else { return }
                        self.scanningState = .complete
                        self.scanningLabel.removeFromSuperview()
                    }
                }
                completion()
            }
            else if self.scanningState == .complete {
                self.actionState.isSuccess = true
                self.changeInfo(text: successfulLivenessCheckText)
                self.closeButton?.isEnabled = false
                self.actionState.status = .waiting
                self.invalidateTimers()
                completion()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    
                    self?._stopRecording { [weak self] in
                        self?.completeAction("Scanning completed") // "Сканирование завершено"
                        return
                    }
                }
   
            }
            else {
                completion()
            }
        }
    }
    
    private func faceStaticProcess(action: OZVerificationMovement, face: VisionFace, completion: @escaping (() -> Void)) {
        if self.actionState.status == .start {
            self.frameView?.strokeColor = OZSDK.customization.ovalCustomization.successStrokeColor
            self.changeFaceReplacementState(state: FaceReplacementState.fixRequired)
            self.actionState.status = .preparing
            self.preparingTimer = Timer.scheduledTimer(timeInterval: livenessPreparingTimeInterval,
                                                       target: self,
                                                       selector: #selector(setRunStatus),
                                                       userInfo: nil,
                                                       repeats: false)
            completion()
            return
        }
        else if self.actionState.status == .preparing {
            _firstFace = face
            completion()
            return
        }
        else if self.actionState.status == .run {
            var actionIsSuccessful : Bool
            switch action {
            case .smile:
                actionIsSuccessful = face.hasSmilingProbability && (face.smilingProbability - (_firstFace?.smilingProbability ?? 0) >= smileThreshold)
            case .eyes:
                actionIsSuccessful = face.hasLeftEyeOpenProbability && face.hasRightEyeOpenProbability && (max(face.leftEyeOpenProbability, face.rightEyeOpenProbability) < eyesThreshold)
            case .right:
                actionIsSuccessful = face.hasHeadEulerAngleY && (face.headEulerAngleY >= rightThreshold)
            case .left:
                actionIsSuccessful = face.hasHeadEulerAngleY && (face.headEulerAngleY <= leftThreshold)
            case .up:
                if  let noseLandmark = face.landmark(ofType: .noseBase),
                    let _firstFace = _firstFace,
                    let _fNoseLandmark = _firstFace.landmark(ofType: .noseBase) {

                    let proportion  = uFaceProportion(face: face,       noseLandmark: noseLandmark)
                    let _proportion = uFaceProportion(face: _firstFace, noseLandmark: _fNoseLandmark)
                    
                    actionIsSuccessful = (proportion - _proportion) < (highThreshold - 1)
                    
                } else {
                    actionIsSuccessful = false
                }
            case .down:
                if let noseLandmark = face.landmark(ofType: .noseBase),
                    let _firstFace = _firstFace,
                    let _fNoseLandmark = _firstFace.landmark(ofType: .noseBase) {

                    let proportion  = dFaceProportion(face: face,       noseLandmark: noseLandmark)
                    let _proportion = dFaceProportion(face: _firstFace, noseLandmark: _fNoseLandmark)

                    actionIsSuccessful = (proportion - _proportion) < (downThreshold - 1)
                } else {
                    actionIsSuccessful = false
                }
            default:
                actionIsSuccessful = false
            }
            if !self.isFullFaceInFrame(face: face) {
                actionIsSuccessful = false
            }
            if actionIsSuccessful {
                self.actionState.isSuccess = true
                self.changeInfo(text: successfulLivenessCheckText)
                self.closeButton?.isEnabled = false
                self.actionState.status = .waiting
                self.invalidateTimers()
                completion()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?._stopRecording { [weak self] in
                        self?.completeAction("Action completed") // "Жест выполнен"
                        return
                    }
                }
            }
            else {
                completion()
            }
        }
        else {
            completion()
        }
    }
    
    private func uFaceProportion(face: VisionFace, noseLandmark: VisionFaceLandmark) -> CGFloat {
        let nosePosition = CGFloat(noseLandmark.position.x.doubleValue)
        let faceOriginX = face.frame.origin.x
        let faceWidth = face.frame.size.width
        return (nosePosition - faceOriginX) / (faceOriginX + faceWidth - nosePosition)
    }
    
    private func dFaceProportion(face: VisionFace, noseLandmark: VisionFaceLandmark) -> CGFloat {
        return 1 / self.uFaceProportion(face: face, noseLandmark: noseLandmark)
    }

    // MARK: - Button action
    
    @objc func startAction(sender: UIButton?) {
        self.actionState.isSuccess = false
//        self.frameView?.changeOpacity(showFace: false)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            sender?.isHidden = true
            guard let currentAction = self.currentAction else { return }
            switch currentAction {
            case .far:
                self.frameView?.animate(finalSize: self.fFaceFrame, duration: self.livenessAnimationTimeInterval)
                self.changeInfo(text: OZResources.localized(key: "Action.Far.Task"))
            case .close:
                self.frameView?.animate(finalSize: self.nFaceFrame, duration: self.livenessAnimationTimeInterval)
                self.changeInfo(text: OZResources.localized(key: "Action.Close.Task"))
            case .smile:
                self.changeInfo(text: OZResources.localized(key: "Action.Smile.Task"))
            case .eyes:
                self.changeInfo(text: OZResources.localized(key: "Action.Eyes.Task"))
            case .down:
                self.changeInfo(text: OZResources.localized(key: "Action.Down.Task"))
            case .up:
                self.changeInfo(text: OZResources.localized(key: "Action.Up.Task"))
            case .left:
                self.changeInfo(text: OZResources.localized(key: "Action.Left.Task"))
            case .right:
                self.changeInfo(text: OZResources.localized(key: "Action.Right.Task"))
            case .scanning:
                self.changeInfo(text: "")
            }
            self.actionState.status = .run
            self.startTimestamp = Date()
            self.startRecording()
            self.setTimer()
            self.setAdditionalTimer()
        }
    }
    
    @objc override func closeAction(sender: UIButton?) {
        // TODO: переписать
        if sender != nil {
            let result = OZVerificationResult(status: .failedBecauseUserCancelled,
                                              movement: currentAction!,
                                              videoURL: nil,
                                              timestamp: Date())
            self.videos.append(result)
        }
        
        self.closeAction("User close liveness controller", withDelegate: sender != nil) // "Пользователь покинул экран"
    }
    
    func closeAction(_ reasonMessage: String = "") {
        self.closeAction(reasonMessage, withDelegate: false)
    }
    
    private static var sSelf: OZLivenessViewController?
    
    private func closeAction(_ reasonMessage: String = "", withDelegate: Bool = false) {
        
        OZLivenessViewController.sSelf = self
        
        self.actionState.status = .cancel
        self.invalidateTimers()
        
        
        if self.actionState.isRecording {
            closeButton?.isEnabled = false
            self.dismiss(animated: true, completion: { [unowned self] in
                self.stopRecording { [unowned self] in
                    self.close(reasonMessage, withDelegate: withDelegate)
                }
            })
        }
        else {
            self.dismiss(animated: true, completion: { [unowned self] in
                self.close(reasonMessage, withDelegate: withDelegate)
                
            })
        }
    }
    
    private func close(_ reasonMessage: String = "", withDelegate: Bool = false) {
        self.addJournalEntry(isAction: false, event: .livenessCheckFinish, context: ["message": reasonMessage])
        self.closeButton?.isEnabled = false
        if self.actionState.isSuccess {
            DispatchQueue.main.asyncAfter(deadline: .now()) { [unowned self] in
                if withDelegate {
                    self.delegate?.onOZVerificationResult(results: self.videos)
                    OZLivenessViewController.sSelf = nil
                }
            }
        }
        else {
            if withDelegate {
                self.delegate?.onOZVerificationResult(results: self.videos)
                OZLivenessViewController.sSelf = nil
            }
        }
    }
    
    private var _lastState: FaceReplacementState?
    
    private func changeFaceReplacementState(state: FaceReplacementState?) {
        if let state = state {
            if state == .fixRequired {
                if state != _lastState {
                    self.addJournalEntry(isAction: true, event: .actionFacePositionFixed)
                }
                self.changeInfo(text: state.text)
            }
            else {
                self.showAttentionMessage(replacementState: state)
            }
        }
        else {
            showAttentionMessage()
        }
        _lastState = state
    }
    
    fileprivate var operationQueue : OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()
    
    fileprivate var stopRecordingOperationQueue : OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()
    
}

// MARK: - Capture

@available(iOS 11.0, *)
extension OZLivenessViewController {
    
    override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        operationQueue.addOperation({ [weak self] in
            guard let `self` = self, CMSampleBufferDataIsReady(sampleBuffer), let currentAction = self.currentAction else { return }
            if self.actionState.status == .run || self.actionState.status == .waiting {
                if self.actionState.isRecording && self.assetWriter?.status == .writing && self.sourceTime == nil {
                    self.sourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    if let sourceTime = self.sourceTime {
                        self.assetWriter?.startSession(atSourceTime: sourceTime)
                    }
                }
                
                if self.assetWriterInput?.isReadyForMoreMediaData == true, self.sourceTime != nil  {
                    self.assetWriterInput?.append(sampleBuffer)
                }
            }
            self.detectFaces(in: sampleBuffer)
        })
    }
    
    private func pAssetWriter() {
        
        guard   let videoOutputUrl = OZFileVideoManager.newVideoURL,
                let assetWriter = try? AVAssetWriter(url: videoOutputUrl,
                                                     fileType: .mp4) else {
            return
        }
        
        let assetWriterInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey:    AVVideoCodecType.h264,
                AVVideoWidthKey:    self.captureImageSize.width,
                AVVideoHeightKey:   self.captureImageSize.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 12000000,
                    AVVideoExpectedSourceFrameRateKey: 30
                ]
            ]
        )
        
        assetWriterInput.expectsMediaDataInRealTime = true
        assetWriterInput.transform = CGAffineTransform(rotationAngle: CGFloat.pi/2)
        
        if assetWriter.canAdd(assetWriterInput) {
            assetWriter.add(assetWriterInput)
        }
        assetWriter.startWriting()
        
        self.sourceTime = nil
        self.assetWriter = assetWriter
        self.assetWriterInput = assetWriterInput
        
        self.addJournalEntry(isAction: true, event: .actionRecordStart)
    }
    
    private func finishWriting(completionHandler handler: @escaping () -> Void){
        self.assetWriter?.finishWriting { [weak self] in
            self?.sourceTime = nil
            handler()
        }
    }
    
    private func startRecording() {
        if !self.actionState.isRecording {
            operationQueue.addOperation { [weak self] in
                self?.actionState.isRecording = true
                self?.pAssetWriter()
            }
        }
    }
    
    private func stopRecording(completion: @escaping (() -> Void)) {
        UIView.animate(withDuration: 1.0, animations: { [weak self] in
            self?.frameView?.alpha = 0
        }) { [weak self] (isSuccess) in
            self?._stopRecording {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
    
    
    
    private func _stopRecording(completion: @escaping (() -> Void)) {
        
        stopRecordingOperationQueue.cancelAllOperations()
        
        guard self.actionState.isRecording else {
            return
        }
        var timeoffset: Double = 0
        let actionIsSuccess = actionState.isSuccess
        if let videoL = self.actionState.startRecordingTimestamp?.timeIntervalSinceNow as? Double,
            -videoL < self.minVideoLength,
            self.actionState.status == .waiting {
            timeoffset += self.minVideoLength + videoL
            if timeoffset < 0 { timeoffset = 0 }
        }
        let actionSessionId = self.actionId
        let scenarioSessionId = self.scenarioId
        
        let operation = StopOperation()
        stopRecordingOperationQueue.addOperation(operation)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoffset) { [weak self] in
            operation.cancel()
        }
        let stopRecordingOperation = StopOperation()
        stopRecordingOperation.mainBlock = { [weak self] in
            guard let self = self else { return }
            self.operationQueue.addOperation { [weak self] in
                guard let self = self else { return }
                self.actionState.status = .final
                self.finishWriting { [weak self] in
                    self?.addJournalEntry(isAction: true, event: .actionRecordFinish)
                    guard let self = self else { return }
                    self.actionState.isRecording = false
                    DispatchQueue.main.async {
                        self.view.isUserInteractionEnabled = true
                    }
                    if let url = self.assetWriter?.outputURL {
                        if actionIsSuccess {
                            self.actionState.outputURL = url
                            self.addJournalEntry(isAction: true, event: .actionRecordSaved)
                        }
                        else {
                            OZFileVideoManager.deleteFile(url: url)
                        }
                    }
                    completion()
                    stopRecordingOperation.cancel()
                }
            }
        }
        stopRecordingOperationQueue.addOperation(stopRecordingOperation)
    }
}

class StopOperation: AsyncOperation { }
class StartOperation: AsyncOperation { }


class AsyncOperation: Operation {
    
    override class func automaticallyNotifiesObservers(forKey key: String) -> Bool {
        return true
    }
    
    init(mainBlock: (() -> Void)? = nil) {
        self.mainBlock = mainBlock
    }
    
    var mainBlock: (() -> Void)?
    
    enum State: String {
        case ready, executing, finished
        fileprivate var keyPath: KeyPath<AsyncOperation, Bool> {
            switch self {
            case .ready:
                return \.isReady
            case .executing:
                return \.isExecuting
            case .finished:
                return \.isFinished
            }
        }
    }
    
    var state: State = State.ready {
        willSet {
            willChangeValue(for: newValue.keyPath)
            willChangeValue(for: state.keyPath)
        }
        didSet {
            didChangeValue(for: oldValue.keyPath)
            didChangeValue(for: state.keyPath)
        }
    }
    
    override var isReady: Bool {
        return super.isReady && state == .ready
    }
    
    override var isExecuting: Bool {
        return state == .executing
    }
    
    override var isFinished: Bool {
        return state == .finished
    }
    
    override var isAsynchronous: Bool {
        return true
    }
    
    override func start() {
        if isCancelled {
            state = .finished
            return
        }
        main()
        state = .executing
    }
    
    private var canceling = false
    
    override func cancel() {
        if isExecuting {
            state = .finished
        }
        else {
            canceling = true
            state = .executing
            state = .finished
        }
    }
    
    override func main() {
        super.main()
        if !canceling {
            self.mainBlock?()
        }
    }
}
