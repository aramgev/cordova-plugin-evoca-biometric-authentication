//
//  OZRequestManager.swift
//  OZLiveness
//
//  Created by Igor Ovchinnikov on 24/07/2019.
//  Copyright © 2019 Igor Ovchinnikov. All rights reserved.
//

import Foundation
import Alamofire
import DeviceKit

@available(iOS 11.0, *)
public struct ResponseError: LocalizedError {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
    
    public var errorDescription: String? {
        return message
    }
}

@available(iOS 11.0, *)
struct ConnectionConfigs {
    
    static var host : String {
        get { return OZSDK.host }
    }
    
    fileprivate static var headers : HTTPHeaders {
        get {
            var headers = [
                "Content-Type" : "application/x-www-form-urlencoded"
            ]
            if let authToken = OZSDK.authToken {
                headers["X-Forensic-Access-Token"] = authToken
            }
            return HTTPHeaders(headers)
        }
    }
}

@available(iOS 11.0, *)
struct OZRequestManager {
    
    private init() { }
    
    private static let alamofireSession : Session = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 300
        return Alamofire.Session(configuration: configuration)
    }()
    
    
    fileprivate static func parseResponseError(data: Data?) -> ResponseError? {
        var error : ResponseError? = nil
        if let data = data, let dict = self.parse(data: data) {
            if let errorMessage = dict["error_message"] as? String {
                error = ResponseError(errorMessage)
            }
        }
        return error
    }
    
    static func login(_ login: String, password: String, completion: @escaping (_ token : String?, _ error: Error?) -> Void) {
        print(#function)
        let parameters : [String: String] = [
            "email"     : login,
            "password"  : password
        ]
        
        
        let url = ConnectionConfigs.host + "/api/authorize/auth"
        alamofireSession.request(url, method: .post,
                                 parameters: ["credentials" : parameters],
                                 encoding: JSONEncoding.default,
                                 headers: ConnectionConfigs.headers).responseJSON { response in
                                    print(#function, response)
                                    
                                    if let data = response.data, let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                                        
                                        
                                        if let error = response.error {
                                            completion(nil, error)
                                            return
                                        }
                                        
                                        if let accessToken = dict["access_token"] as? String {
                                            if (accessToken.trimmingCharacters(in: .whitespaces).isEmpty == false) {
                                                completion(accessToken, nil)
                                                return
                                            }
                                        }
                                        
                                        if let errorMessage = dict["error_message"] as? String {
                                            let responseError = ResponseError(errorMessage)
                                            completion(nil, responseError)
                                            return
                                        }
                                        completion(nil, BiometricAuthenticationError.credentialsNotProvided)
                                    } else {
                                        completion(nil, response.error)
                                    }
        }
    }
    
    static func analyse(folderId: String? = nil, results: [OZVerificationResult], analyseStates: Set<OZAnalysesState>, fileUploadProgress: @escaping ((Progress) -> Void), completion: @escaping ( _ resolution : AnalyseResolutionStatus?, _ error: Error?) -> Void) {
        self.addToFolder(folderId: folderId, results: results, analyseStates: analyseStates, fileUploadProgress: fileUploadProgress) { (folderId, error) in
            if let folderId = folderId {
                self.addAnalyses(folderID: folderId, states: analyseStates, completion: completion)
            }
            else {
                completion(nil, error)
            }
        }
    }
    
    static func addToFolder(folderId: String? = nil, results: [OZVerificationResult], analyseStates: Set<OZAnalysesState>, fileUploadProgress: @escaping ((Progress) -> Void), completion: @escaping (_ folderId : String?, _ error: Error?) -> Void) {
        var videos : [String : URL] = [:]
        var mediaTags : [String : [String]] = [:]
        for i in 0 ..< results.count {
            let key = "video_\(i)"
            videos[key] = results[i].videoURL
            let actionTag : String
            switch results[i].movement {
            case .far:
                actionTag = "video_selfie_zoom_out"
            case .close:
                actionTag = "video_selfie_zoom_in"
            case .smile:
                actionTag = "video_selfie_smile"
            case .eyes:
                actionTag = "video_selfie_eyes"
            case .up:
                actionTag = "video_selfie_high"
            case .down:
                actionTag = "video_selfie_down"
            case .left:
                actionTag = "video_selfie_left"
            case .right:
                actionTag = "video_selfie_right"
            case .scanning:
                actionTag = "video_selfie_scan"
            }
            mediaTags[key] = [
                "video_selfie",
                actionTag,
                "orientation_portrait"
            ]
        }
        self.addToFolder(folderId: folderId, videos: videos, mediaTags: mediaTags, fileUploadProgress: fileUploadProgress, completion: completion)
    }
    
    private static func addToFolder(folderId: String? = nil, videos: [String: URL], mediaTags: [String:[String]], fileUploadProgress: @escaping ((Progress) -> Void), completion: @escaping (_ folderId : String?, _ error: Error?) -> Void) {
        let url: String

        if let folderId = folderId {
            url = ConnectionConfigs.host + "/api/folders/" + "\(folderId)/" + "media/"
        }
        else {
            url = ConnectionConfigs.host + "/api/folders/?"
        }
        
        let request = alamofireSession.request(url, method: .post,
                                               encoding: JSONEncoding.default,
                                               headers: ConnectionConfigs.headers)
        
        alamofireSession.upload(multipartFormData: { multipartFormData in
            for key in videos.keys {
                multipartFormData.append(videos[key]!, withName: key)
            }
            
            let payload = [
                "media:tags" : mediaTags,
                "folder:meta_data" : [
                    "phone_info" : [
                        "manufacturer" : "Apple",
                        "model" : Device.current.model,
                        "device" : Device.current.description,
                        "os_version" : Device.current.systemVersion,
                        "version_liveness_sdk" : OZSDK.version
                    ] as [String : Any]
                ] as [String : Any]
            ] as [String : Any]
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload,
                                                          options: .prettyPrinted) {
                multipartFormData.append(jsonData, withName: "payload")
            }
        }, with: request.convertible)
            .uploadProgress(closure: fileUploadProgress)
            .responseJSON { response in
            if let data = response.data {
                if let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    completion(dict["folder_id"] as? String, response.error)
                    return
                }
                else if let folderId = folderId, let array = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]], array.count > 0 {
                    completion(folderId, response.error)
                    return
                }
            }
            completion(nil, response.error)
        }
    }
    
    private static func addAnalyses(folderID: String, states: Set<OZAnalysesState>, completion: @escaping (_ resolution : AnalyseResolutionStatus?, _ error: Error?) -> Void) {
        guard states.count > 0 else { return completion(nil, nil) }
        let parameters : [[String: String]] = states.map { (state) -> [String: String] in
            return ["type": state.rawValue]
        }
        
        let url = ConnectionConfigs.host + "/api/folders/" + folderID + "/analyses"
        alamofireSession.request(url, method: .post,
                                 parameters: ["analyses" : parameters],
                                 encoding: JSONEncoding.default,
                                 headers: ConnectionConfigs.headers).responseJSON { response in
                                    if  let data = response.data,
                                        let answer = self.parse(data: data)  {
                                        if  let analyseID = answer["analyse_id"] as? String,
                                            let resolution = answer["resolution"] as? String,
                                            let resolutionStatus = AnalyseResolutionStatus(rawValue: resolution) {
                                            if resolutionStatus == .processing || resolutionStatus == .initial {
                                                self.waitAnalysesStatus(analyseID: analyseID, completion: completion)
                                            }
                                            else {
                                                completion(resolutionStatus, response.error)
                                            }
                                        }
                                        else {
                                            completion(nil, response.error)
                                        }
                                    }
                                    else {
                                        completion(nil, response.error)
                                    }
        }
    }
    
    private static func waitAnalysesStatus(analyseID: String,completion: @escaping (_ resolution : AnalyseResolutionStatus?, _ error: Error?) -> Void) {
        let url = ConnectionConfigs.host + "/api/analyses/" + analyseID
        alamofireSession.request(url, method: .get,
                                 encoding: JSONEncoding.default,
                                 headers: ConnectionConfigs.headers).responseJSON { response in
                                    if  let data = response.data,
                                        let answer = self.parse(data: data) {
                                        if  let resolution = answer["resolution"] as? String,
                                            let resolutionStatus = AnalyseResolutionStatus(rawValue: resolution) {
                                            if resolutionStatus == .processing || resolutionStatus == .initial {
                                                completion(resolutionStatus, response.error)
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                                                    self.waitAnalysesStatus(analyseID: analyseID, completion: completion)
                                                })
                                            }
                                            else {
                                                completion(resolutionStatus, response.error)
                                            }
                                        }
                                        else {
                                            completion(nil, response.error)
                                        }
                                    }
                                    else {
                                        completion(nil, response.error)
                                    }
        }
    }
    
    private static func parse(data: Data) -> [String: Any]? {
        if let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            return dict
        }
        else if let array = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any], let dict = array.last as? [String: Any]  {
            return dict
        }
        return nil
    }
    
    private static func parseArray(data: Data) -> [[String: Any]]? {
        if let array = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]  {
            return array
        }
        return nil
    }
    
}

@available(iOS 11.0, *)
extension DataResponse {
    var error: Error? {
        switch result {
        case .success:
            return nil
        case .failure(let error):
            return OZRequestManager.parseResponseError(data: self.data) ?? error
        }
    }
}
// MARK: - Regula Extension
@available(iOS 11.0, *)
extension OZRequestManager {
    
        
    static func analyse(folderId: String? = nil,
                        frontDocumentPhoto: URL?,
                        backDocumentPhoto: URL?,
                        results: [OZVerificationResult],
                        analyseStates: Set<OZAnalysesState>,
                        scenarioState: @escaping ((_ state: ScenarioState) -> Void),
                        fileUploadProgress: @escaping ((Progress) -> Void),
                        completion: @escaping (_ folderResolutionStatus: AnalyseResolutionStatus?, _ resolutions : [AnalyseResolution]?, _ error: Error?) -> Void) {
        self.getBLCollectionID { (collectionId, error) in
            if error == nil {
                self.addToFolder(folderId: folderId, frontDocumentPhoto: frontDocumentPhoto, backDocumentPhoto: backDocumentPhoto, results: results, analyseStates: analyseStates, scenarioState: scenarioState, fileUploadProgress: fileUploadProgress) { (folderId, documentPhotosMediaIds, frontDocumentMediaId, livenessVideoMediaIds , error) in
                    if let folderId = folderId {
                        self.addAnalyses(collectionId:          collectionId,
                                         documentMediaIds:      documentPhotosMediaIds,
                                         frontDocumentMediaId:  frontDocumentMediaId,
                                         livenessMediaIds:      livenessVideoMediaIds,
                                         folderID:              folderId,
                                         states:                analyseStates,
                                         scenarioState:         scenarioState,
                                         completion:            completion)
                    }
                    else {
                        completion(nil, nil, error)
                    }
                }
            }
            else {
                completion(nil, nil, error)
            }
        }
    }
    
    static func getBLCollectionID(completion: @escaping (_ collectionId : String?, _ error: Error?) -> Void) {
        let url = ConnectionConfigs.host + "/api/collections"
        alamofireSession.request(url,
                                 method: .get,
                                 parameters: nil,
                                 encoding: JSONEncoding.default,
                                 headers: ConnectionConfigs.headers).responseJSON { response in
                                    if  let data = response.data,
                                        let answer = self.parseArray(data: data)  {
                                        let answer = answer.first(where: { (element) -> Bool in
                                            return element["alias"] as? String == "blacklist"
                                        })
                                        if let collectionId = answer?["collection_id"] as? String {
                                            completion(collectionId, response.error)
                                            return
                                        }
                                    }
                                    completion(nil, response.error)
        }
    }
    
    static func addToFolder(folderId: String? = nil, frontDocumentPhoto: URL?, backDocumentPhoto: URL?, results: [OZVerificationResult], analyseStates: Set<OZAnalysesState>, scenarioState: @escaping ((_ state: ScenarioState) -> Void), fileUploadProgress: @escaping ((Progress) -> Void), completion: @escaping (_ folderId : String?, _ documentPhotosMediaIds : [String]?, _ frontDocumentMediaId: String?, _ livenessVideoMediaIds : [String]?, _ error: Error?) -> Void) {
        scenarioState(.addToFolder)
        var mediaTags : [String : [String]] = [:]
        var files : [String : URL] = [:]
        if let frontDocumentPhoto = frontDocumentPhoto {
            let key = "photo_document_front"
            files[key] = frontDocumentPhoto
            
            mediaTags[key] = [
                "photo_id_front"
            ]
        }
        if let backDocumentPhoto = backDocumentPhoto {
            let key = "photo_document_back"
            files[key] = backDocumentPhoto

            mediaTags[key] = [
                "photo_id_back"
            ]
        }
        for i in 0 ..< results.count {
            let key = "video_\(i)"
            files[key] = results[i].videoURL
            let actionTag : String
            switch results[i].movement {
            case .far:
                actionTag = "video_selfie_zoom_out"
            case .close:
                actionTag = "video_selfie_zoom_in"
            case .smile:
                actionTag = "video_selfie_smile"
            case .eyes:
                actionTag = "video_selfie_eyes"
            case .up:
                actionTag = "video_selfie_high"
            case .down:
                actionTag = "video_selfie_down"
            case .left:
                actionTag = "video_selfie_left"
            case .right:
                actionTag = "video_selfie_right"
            case .scanning:
                actionTag = "video_selfie_scan"
            }
            mediaTags[key] = [
                "video_selfie",
                actionTag,
                "orientation_portrait"
            ]
        }
        self.addToFolder(folderId: folderId, filesDescription: files, mediaTags: mediaTags, scenarioState: scenarioState, fileUploadProgress: fileUploadProgress, completion: completion)
    }
    
    private static func addToFolder(folderId: String? = nil, filesDescription: [String: URL], mediaTags: [String:[String]], scenarioState: @escaping ((_ state: ScenarioState) -> Void), fileUploadProgress: @escaping ((Progress) -> Void), completion: @escaping (_ folderId : String?, _ documentPhotosMediaIds : [String]?, _ frontDocumentMediaId: String?, _ livenessVideoMediaIds : [String]?, _ error: Error?) -> Void) {
        let url: String
        
        if let folderId = folderId {
            url = ConnectionConfigs.host + "/api/folders/" + "\(folderId)/" + "media/"
        }
        else {
            url = ConnectionConfigs.host + "/api/folders/?"
        }
        
        let request = alamofireSession.request(url, method: .post,
                                               encoding: JSONEncoding.default,
                                               headers: ConnectionConfigs.headers)
        
        alamofireSession.upload(multipartFormData: { multipartFormData in
            for key in filesDescription.keys {
                multipartFormData.append(filesDescription[key]!, withName: key)
            }
            
            let payload = [
                "media:tags" : mediaTags,
                "folder:meta_data" : [
                    "phone_info" : [
                        "manufacturer" : "Apple",
                        "model" : Device.current.model,
                        "device" : Device.current.description,
                        "os_version" : Device.current.systemVersion,
                        "version_liveness_sdk" : OZSDK.version
                        ] as [String : Any?]
                    ] as [String : Any]
                ] as [String : Any]
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload,
                                                          options: .prettyPrinted) {
                multipartFormData.append(jsonData, withName: "payload")
            }
        }, with: request.convertible)
            .uploadProgress(closure: fileUploadProgress)
            .responseJSON { response in
            if let data = response.data {
                if let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    var photoMediaIds = [String]()
                    var videoMediaIds = [String]()
                    var frontMediaId : String?
                    if let media = dict["media"] as? [[String: Any]] {
                        for submedia in media {
                            if let mediaId = submedia["media_id"] as? String {
                                // TODO: сравнивать имена файлов
                                if submedia["media_type"] as? String == "IMAGE_FOLDER"  {
                                    if let tags = submedia["tags"] as? [String] {
                                        for tag in tags {
                                            if tag == "photo_id_front" {
                                                frontMediaId = mediaId
                                            }
                                        }
                                    }
                                    photoMediaIds.append(mediaId)
                                }
                                else if submedia["media_type"] as? String == "VIDEO_FOLDER" {
                                    videoMediaIds.append(mediaId)
                                }
                            }
                        }
                    }
                    completion(dict["folder_id"] as? String, photoMediaIds, frontMediaId, videoMediaIds, response.error)
                    return
                }
                else if let folderId = folderId, let array = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]], array.count > 0 {
                    completion(folderId, nil, nil, nil, response.error)
                    return
                }
            }
            completion(folderId, nil, nil, nil, response.error)
        }
    }
    
    private static func addAnalyses(collectionId: String?, documentMediaIds: [String]? = nil, frontDocumentMediaId: String?, livenessMediaIds: [String]? = nil, folderID: String, states: Set<OZAnalysesState>, scenarioState: @escaping ((_ state: ScenarioState) -> Void), completion: @escaping (_ folderResolutionStatus: AnalyseResolutionStatus?, _ resolutions : [AnalyseResolution]?, _ error: Error?) -> Void) {
        scenarioState(.addAnalyses)
        guard states.count > 0 else { return completion(nil, nil, nil) }
        var parameters : [[String: Any]] = states.map { (state) -> [String: Any] in
            var params = [
                "type": state.rawValue
            ] as [String: Any]
            if let livenessMediaIds = livenessMediaIds {
                params["source_media"] = livenessMediaIds
            }
            return params
        }
        
        if let documentMediaIds = documentMediaIds {
            parameters.append([
                "type": "documents",
                "source_media": documentMediaIds,
                "params": [
                    "capabilities": 492
                ]
            ])
        }
        
        if let livenessMediaIds = livenessMediaIds, let frontDocumentMediaId = frontDocumentMediaId {
            parameters.append([
                "type": "biometry",
                "source_media": livenessMediaIds + [frontDocumentMediaId]
            ])
        }
        
        if let collectionId = collectionId {
            if let livenessMediaIds = livenessMediaIds, let frontDocumentMediaId = frontDocumentMediaId {
                parameters.append([
                    "type": "collection",
                    "params": [
                        "collection_id": collectionId,
                        "decision_count": 10,
                        "decision_threshold": 0.7,
                        "source_media" : livenessMediaIds + [frontDocumentMediaId]
                    ]
                ])
            }
        }

        
        let url = ConnectionConfigs.host + "/api/folders/" + folderID + "/analyses"
        alamofireSession.request(url, method: .post,
                                 parameters: ["analyses" : parameters],
                                 encoding: JSONEncoding.default,
                                 headers: ConnectionConfigs.headers).responseJSON { response in
                                    if  let data = response.data,
                                        let answer = self.parse(data: data)  {
                                          if    let resolution = answer["resolution"] as? String,
                                                let resolutionStatus = AnalyseResolutionStatus(rawValue: resolution) {
                                            scenarioState(.waitAnalisesResult)
                                            self.waitAnalysesStatus(folderID: folderID, completion: completion)
                                        }
                                        else {
                                            completion(nil, nil, response.error)
                                        }
                                    }
                                    else {
                                        completion(nil, nil, response.error)
                                    }
        }
    }
    
    private static func waitAnalysesStatus(folderID: String, completion: @escaping (_ folderResolutionStatus: AnalyseResolutionStatus?, _ resolutions : [AnalyseResolution]?, _ error: Error?) -> Void) {
        let url = ConnectionConfigs.host + "/api/folders/" + folderID + "?with_analyses=true"
        alamofireSession.request(url, method: .get,
                                 encoding: JSONEncoding.default,
                                 headers: ConnectionConfigs.headers).responseJSON { response in
                                    if  let data = response.data,
                                        let answer = self.parse(data: data) {
                                        if  let resolution = answer["resolution_status"] as? String,
                                            let folderResolutionStatus = AnalyseResolutionStatus(rawValue: resolution) {

                                            var resolutions : [AnalyseResolution] = []
                                            if let analyses = answer["analyses"] as? [[String: Any]] {
                                                for analyse in analyses {
                                                    if  var type = analyse["type"] as? String,
                                                        let rawResolutionStatus = analyse["resolution_status"] as? String,
                                                        let resolutionStatus = AnalyseResolutionStatus(rawValue: rawResolutionStatus) {
                                                        
                                                        if resolutionStatus == .processing || resolutionStatus == .initial {
                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                                                                self.waitAnalysesStatus(folderID: folderID, completion: completion)
                                                            })
                                                            return
                                                        }
                                                        
                                                        if type == "DOCUMENTS", let results = analyse["results_data"] as? [String: Any], let tfs = results["text_fields"] as? [[String: Any]] {
                                                            var documentBlocks = [DocumentDataBlock]()
                                                            tfs.forEach { (dict) in
                                                                if let fName = dict["field_name"] as? String {
                                                                    documentBlocks.append(
                                                                        DocumentDataBlock(
                                                                            fieldName: fName,
                                                                            visual: dict["visual"] as? String,
                                                                            mrz: dict["mrz"] as? String
                                                                        )
                                                                    )
                                                                }
                                                            }
                                                            let resolution = DocumentAnalyseResolution(type: type, status: resolutionStatus)
                                                            resolution.documentData = documentBlocks
                                                            resolutions.append(resolution)
                                                        }
                                                        else if  type == "COLLECTION",
                                                            let collection = analyse["collection"] as? [String: Any],
                                                            let alias = collection["alias"] as? String {
                                                            type += " [\(alias)]"
                                                            resolutions.append(AnalyseResolution(type: type, status: resolutionStatus))
                                                        }
                                                        else {
                                                            resolutions.append(AnalyseResolution(type: type, status: resolutionStatus))
                                                        }
                                                    }
                                                    else {
                                                        completion(folderResolutionStatus, resolutions, ResponseError("Ошибка парсинга"))
                                                        return
                                                    }
                                                }
                                            }
                                            completion(folderResolutionStatus, resolutions, response.error)
                                        }
                                        else {
                                            completion(nil, nil, response.error)
                                        }
                                    }
                                    else {
                                        completion(nil, nil, response.error)
                                    }
        }
    }
}
