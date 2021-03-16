//
//  OZJournal.swift
//  OZLivenessSDK
//
//  Created by Igor Ovchinnikov on 29.10.2019.
//

import UIKit
//import RealmSwift

@available(iOS 11.0, *)
extension OZVerificationMovement {
    var code : String {
        switch self {
        case .close:
            return "close"
        case .down:
            return "down"
        case .eyes:
            return "eyes"
        case .far:
            return "far"
        case .left:
            return "left"
        case .right:
            return "right"
        case .scanning:
            return "scanning"
        case .smile:
            return "smile"
        case .up:
            return "up"
        }
    }
}

extension OZJournalEvent {
    var text : String {
        switch self {
        case .actionFacePositionFixed:
            return "Face fixed"//"Лицо зафиксировано"
        case .actionFinish:
            return "Action completed"//"Выполнение жеста завершено"
        case .actionRecordFinish:
            return "Action recording completed"//"Запись жеста завершена"
        case .actionRecordSaved:
            return "Action record saved"//"Запись жеста сохранена"
        case .actionRecordStart:
            return "Action recording started"//"Запись жеста запущена"
        case .actionRestart:
            return "Action restart"//"Жест перезапущен"
        case .actionStart:
            return "Start action"//"Начало выполнения жеста"
        case .error:
            return "Error"//"Ошибка"
        case .unknown:
            return "Unknown"//"Неизвестное событие"
        case .livenessSessionInitialization:
            return "SDK Initialization"//"Инициализация SDK"
        case .livenessCheckStart:
            return "Liveness check start"//"Начало проверки"
        case .livenessCheckFinish:
            return "Liveness check finish"//"Завершение проверки"
        }
    }
}

func +<K, V1, V2> (left: [K : V1], right: [K : V2]) -> [K : AnyObject] {
    var result = [K : AnyObject]()
    
    for (k, v) in left {
        result[k] = v as AnyObject?
    }
    
    for (k, v) in right {
        result[k] = v as AnyObject?
    }
    
    return result
}

typealias OZJournalContext = [String: Any]

class OZJournal {
    let sessionId: String = UUID().uuidString
    static let sharedInstance = OZJournal()
    private init() { }
    
    static let realmOperationQueue : OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .default
        return operationQueue
    }()
    
//    fileprivate static var realmConfig : Realm.Configuration = {
//        let config = Realm.Configuration(deleteRealmIfMigrationNeeded: true)
//        return config
//    }()
//
//    fileprivate static var realm : Realm {
//        get {
//            let realm = try! Realm(configuration: self.realmConfig)
//            return realm
//        }
//    }
    
    public func getCurrentEntries(completion: @escaping (_ entries : [OZJournalEntry]) -> Void) {
//        DispatchQueue.global(qos: .background).async {
//            OZJournal.realmOperationQueue.addOperation {
//                let realm = OZJournal.realm
//                realm.refresh()
//                let entries = realm.objects(OZJournalEntry.self)
//                completion(Array(entries))
//            }
//        }
    }
    
    public func removeAll(completion: @escaping () -> Void) {
//        DispatchQueue.global(qos: .background).async {
//            OZJournal.realmOperationQueue.addOperation {
//                let realm = OZJournal.realm
//                realm.refresh()
//                let entries = realm.objects(OZJournalEntry.self)
//                realm.refresh()
//                realm.beginWrite()
//                realm.delete(entries)
//                do {
//                    try realm.commitWrite()
//                }
//                catch {
//                    DispatchQueue.main.async {
//                        completion()
//                        return
//                    }
//                }
//                DispatchQueue.main.async {
//                    completion()
//                    return
//                }
//            }
//        }
    }
    
    func pStringCallback(event: OZJournalEvent, context: OZJournalContext?) -> String {
        var text = "Event: " + event.text

        if  let context = context {
            let pMeta = self.pContext(context: context)
            if  let jsonData = try? JSONSerialization.data(withJSONObject: pMeta, options: []),
                let string = String(data: jsonData, encoding: .utf8) {
                text += "\n"
                text += "Context: " + string
            }
        }
        return text
    }
    
    func addEntry(event: OZJournalEvent, context: OZJournalContext? = nil, actionSessionId: String? = nil, scenarioSessionId: String? = nil, completion: @escaping (_ isSuccess : Bool) -> Void = { (true) in }) {
        
        if #available(iOS 11.0, *) {
            SDK._journalObserver(self.pStringCallback(event: event, context: context))
        }
        
        return

//        DispatchQueue.global(qos: .background).async {
//            OZJournal.realmOperationQueue.addOperation {
//
//                var metaStr : String?
//                if let context = context {
//                    do {
//                        let pMeta = self.pContext(context: context)
//                        let jsonData = try JSONSerialization.data(withJSONObject: pMeta, options: [])
//                        metaStr = String(data: jsonData, encoding: .utf8)
//                    }
//                    catch {
//                        assert(true, "addEntry meta json")
//                    }
//                }
//                let entry = OZJournalEntry(event: event, context: metaStr)
//                entry.actionSessionId = actionSessionId
//                entry.scenarioSessionId = scenarioSessionId
//                autoreleasepool {
//                    let realm = OZJournal.realm
//                    realm.refresh()
//                    realm.beginWrite()
//                    do {
//                        realm.add(entry)
//                        try realm.commitWrite()
//                    }
//                    catch {
//                        DispatchQueue.main.async {
//                            completion(false)
//                            return
//                        }
//                    }
//                }
//                DispatchQueue.main.async {
//                    completion(true)
//                }
//            }
//        }
    }
    
    private func pContext(context: [String: Any]) -> [String: Any] {
        var pContext = context
        for key in context.keys {
            if let date = context[key] as? Date {
                pContext[key] = date.timeIntervalSince1970
            }
            else if pContext[key] == nil {
                pContext[key] = NSNull()
            }
            else {
                if var subData = pContext[key] as? [[String: Any]] {
                    if subData.count == 0 {
                        pContext[key] = NSNull()
                    }
                    else {
                        for i in 0..<subData.count {
                            subData[i] = self.pContext(context: subData[i])
                        }
                        pContext[key] = subData
                    }
                }
                else if let subData = pContext[key] as? [String: Any] {
                    pContext[key] = self.pContext(context: subData)
                }
            }
        }
        return pContext
    }
    
}

public enum OZJournalEvent : String {
    case unknown                        = ""
    case livenessSessionInitialization  = "liveness_session_initialization"
    case livenessCheckStart         = "liveness_check_start"
    case actionStart                = "action_start"
    case actionRestart              = "action_restart"
    case actionFinish               = "action_finish"
    case livenessCheckFinish        = "liveness_check_finish"
    case actionFacePositionFixed    = "action_face_position_fixed"
    case actionRecordStart          = "action_record_start"
    case actionRecordFinish         = "action_record_finish"
    case actionRecordSaved          = "action_record_saved"
    case error                      = "error"
}

public class OZJournalEntry {//: Object {
    
//    override public static func primaryKey() -> String? {
//        return "id"
//    }
    
    public var event : OZJournalEvent? {
        get { return OZJournalEvent(rawValue: eventRaw) }
        set { self.eventRaw = newValue?.rawValue ?? "" }
    }
    
    var sessionId: String {
        get { return OZJournal.sharedInstance.sessionId }
    }
    
    
    @objc dynamic var eventRaw          : String = ""
    @objc dynamic var id                : String = UUID().uuidString
    @objc public dynamic var actionSessionId   : String?
    @objc public dynamic var scenarioSessionId : String?
    
    @objc public dynamic var context    : String?
    @objc public dynamic var timestamp  : Date =  Date()
    
    convenience required init(event: OZJournalEvent, context: String? = nil) {
        self.init()
        self.event      = event
        self.context    = context
    }
    
    var jsonParameters : [String: Any?] {
        get {
            var params : [String: Any?] = ["event" : eventRaw, "timestamp": timestamp.timeIntervalSince1970]
            if let data = context?.data(using: .utf8) {
                do {
                    let context = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    params = params + ["context": context]
                    return params
                } catch {
                    assert(true, "Проблема с хранением JSON в OZJournalEntry")
                }
            }
            return params
        }
    }
}
