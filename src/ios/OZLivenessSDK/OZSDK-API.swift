
import Foundation
import UIKit


/** Конфигурации внешнего вида OZ. */
@available(iOS 11.0, *)
public struct OZCustomization {
    
    /** Цвет текста.  */
    public var textColor : UIColor
    /** Цвет кнопок.  */
    public var buttonColor : UIColor
    
    /** Конфигурации для овала, ограничевающего область в которой должно размещаться лицо.  */
    public var ovalCustomization           : OZOvalCustomization
}

/** Конфигурации для овала, ограничевающего область в которой должно размещаться лицо. */
@available(iOS 11.0, *)
public struct OZOvalCustomization {
    /** Ширина контура овала. */
    public var strokeWidth              : CGFloat
    /** Цвет контура овала. Удачное размещение лица. */
    public var successStrokeColor       : UIColor
    /** Цвет контура овала. Неудачное размещение лица. */
    public var failStrokeColor          : UIColor
}

/** Конфигурации для порогов, нужны для отладки жестов. Рекомендуется использовать значения по-умолчанию. */
@available(iOS 11.0, *)
public struct OZLivenessThresholdSettings {
    /** Порог ошибки для определения центра лица. */
    public var centerError  : CGFloat
    /** Порог ошибки для определения высоты лица. */
    public var heightError  : CGFloat
    
    /** Порог для степени улыбки. */
    public var smilingProbability   : CGFloat
    /** Порог для степени открытости глаз. */
    public var eyesOpenProbability  : CGFloat
    
    /** Порог для угла поворота головы. */
    public var headEulerAngleYAbs   : CGFloat
    
    /** Порог для угла поворота головы налево. */
    public var leftHeadEulerAngleY  : CGFloat {
        get { return -headEulerAngleYAbs }
    }
    
    /** Порог для угла поворота головы направо. */
    public var rightHeadEulerAngleY : CGFloat {
        get { return  headEulerAngleYAbs }
    }
    
    public var startSmilingProbability     : CGFloat
    public var startEyesOpenProbability    : CGFloat
    public var centerEulerAngleY           : CGFloat
    
    /** Порог для степени наклона головы. */
    public var downFaceProbability : CGFloat
    /** Порог для степени приподнятости головы. */
    public var highFaceProbability : CGFloat
    /** Соотношение верхней и  нижней части лица без наклона. */
    public let normalFaceProportion : CGFloat = 1.2
    
    public var brightnessSetting : CGFloat = 0.3
}

/** Конфигурации для рамки, ограничевающей область в которой должно размещаться лицо. */
@available(iOS 11.0, *)
public struct OZFrameCustomization {
    /** Цвет фона рамки. */
    public var backgroundColor: UIColor
}

@available(iOS 11.0, *)
public var OZSDK: OZSDKProtocol = SDK()

/** Интерфейс для конфигурирования SDK и получения результатов liveness-проверки. */
@available(iOS 11.0, *)
public protocol OZSDKProtocol {
    
    /** */
    var journalObserver: ((String) -> Void) { get set }
    
    /** Настройка локализации сообщений для liveness-проверки. Доступна en и ru. Если не указано, то локализация будет работать автоматически */
    var localizationCode: OZLocalizationCode? {
        set
        get
    }
    
    /** Токен для отправки запроса анализа liveness-видео. */
    var authToken: String? {
        set
        get
    }
    
    /** Хост для отправки запроса анализа liveness-видео. */
    var host: String {
        set
        get
    }
    
    /** Настройки для числа попыток */
    var attemptSettings: OZAttemptSettings {
        set
        get
    }
    
    /** Конфигурация внешнего вида OZ. */
    var customization: OZCustomization {
        set
        get
    }
    
    /** Версия SDK. */
    var version: String { get }
    
    /** Пороги для liveness-проверок. */
    var thresholdSettings : OZLivenessThresholdSettings { get set }
    
    /** Метод для авторизации. */
    func login(_ login: String, password: String, completion: @escaping (_ token : String?, _ error: Error?) -> Void)
    
    /** Метод создания контроллера для проведения liveness-проверки. */
    func createVerificationVCWithDelegate(_ delegate: OZVerificationDelegate, actions: [OZVerificationMovement]) -> UIViewController
    
    /** Метод создания контроллера для тестирования порогов срабатывания. */
    func createTestVerificationVC() -> UIViewController
    
    /** Метод отправки запроса анализа liveness-видео. */
    func analyse(results: [OZVerificationResult],
                 analyseStates: Set<OZAnalysesState>,
                 fileUploadProgress: @escaping ((Progress) -> Void),
                 completion: @escaping ( _ resolution : AnalyseResolutionStatus?, _ error: Error?) -> Void)
    
    /** Метод отправки запроса добавления видео в папку и дальнейшего анализа liveness-видео. */
    func analyse(folderId: String,
                 results: [OZVerificationResult],
                 analyseStates: Set<OZAnalysesState>,
                 fileUploadProgress: @escaping ((Progress) -> Void),
                 completion: @escaping ( _ resolution : AnalyseResolutionStatus?, _ error: Error?) -> Void)
    
    /** Метод отправки запроса добавления видео в папку. */
    func addToFolder(results: [OZVerificationResult],
                     analyseStates: Set<OZAnalysesState>,
                     fileUploadProgress: @escaping ((Progress) -> Void),
                     completion: @escaping (_ folderId : String?, _ error: Error?) -> Void)
    
    /** Метод отправки запроса добавления видео в папку c folderId. */
    func addToFolder(folderId: String,
                     results: [OZVerificationResult],
                     analyseStates: Set<OZAnalysesState>,
                     fileUploadProgress: @escaping ((Progress) -> Void),
                     completion: @escaping (_ folderId : String?, _ error: Error?) -> Void)
    
    func documentAnalyse(documentPhoto: DocumentPhoto,
                         results: [OZVerificationResult],
                         analyseStates: Set<OZAnalysesState>,
                         scenarioState: @escaping ((_ state: ScenarioState) -> Void),
                         fileUploadProgress: @escaping ((Progress) -> Void),
                         completion: @escaping (_ folderResolutionStatus: AnalyseResolutionStatus?, _ resolutions : [AnalyseResolution]?, _ error: Error?) -> Void)
    
    /** Удаление всех записанных видео. */
    func cleanTempDirectory()
}

public struct DocumentPhoto {
    public init (front: URL?, back: URL?) {
        self.front  = front
        self.back   = back
    }
    public var front    : URL?
    public var back     : URL?
}

/** Конфигурации анализа видео. */
@available(iOS 11.0, *)
public enum OZAnalysesState: String {
    case liveness   = "liveness"
    case quality    = "quality"
}

/** Делегат, возвращающий результаты и состояния liveness-проверки. */
@available(iOS 11.0, *)
public protocol OZVerificationDelegate: class {
    /** Метод, возвращающий результаты liveness-проверки. */
    func onOZVerificationResult(results: [OZVerificationResult])
}

/** Структура, содержащая результат liveness-проверки. */
@available(iOS 11.0, *)
public struct OZVerificationResult {
    /** Статус liveness-проверки. */
    public var status      : OZVerificationStatus
    /** Тип движения liveness-проверки. */
    public var movement    : OZVerificationMovement
    /** Путь к видео, с liveness-проверкой. */
    public var videoURL    : URL?
    /** Временная метка окончания проверки. */
    public var timestamp   : Date
}

/** Статус liveness-проверки. */
@available(iOS 11.0, *)
public enum OZVerificationStatus {
    /** Успешное прохождение liveness-проверки. */
    case userProcessedSuccessfully
    /** Liveness-проверка не была обработана. */
    case userNotProcessed
    /** Liveness-проверка была прервана пользователем. */
    case failedBecauseUserCancelled
    /** Liveness-проверка не возможна, т.к. не предоставлен доступ к камере. */
    case failedBecauseCameraPermissionDenied
    /** Liveness-проверка не возможна, т.к. приложение было погружено в фон. */
    case failedBecauseOfBackgroundMode
    /** Liveness-проверка прервана по времени. */
    case failedBecauseOfTimeout
    /** Liveness-проверка прервана по причине исчерпания попыток */
    case failedBecauseOfAttemptLimit
    /** Liveness-проверка прервана по ограничению памяти. */
    case failedBecauseOfLowMemory
}

/** Настройка числа попыток */
@available(iOS 11.0, *)
public struct OZAttemptSettings {
    /** Число попыток для каждого жеста */
    var singleCount: Int?
    /** ОБщее число попыток */
    var commonCount: Int?
    
    public init(singleCount: Int? = nil, commonCount: Int? = nil) {
        self.singleCount = singleCount
        self.commonCount = commonCount
    }
}

/** Движения для liveness-проверки. */
@available(iOS 11.0, *)
public enum OZVerificationMovement {
    
    // MARK: - actions
    
    /** Приближение лица к камере. */
    case close
    /** Удаление лица от камеры. */
    case far
    /** Определение улыбки. */
    case smile
    /** Определение закрытых глаз. */
    case eyes
    /** Сканирование. */
    case scanning
    
    
    // MARK: - beta actions
    
    /** Поворот влево. */
    case left
    /** Поворот вправо. */
    case right
    /** Наклон головы вниз. */
    case down
    /** Направление головы вверх. */
    case up
    
}

@available(iOS 11.0, *)
public class AnalyseResolution {
    public var status: AnalyseResolutionStatus
    public var type: String
    
    init(type: String, status: AnalyseResolutionStatus) {
        self.status = status
        self.type = type
    }
}

@available(iOS 11.0, *)
public class DocumentAnalyseResolution: AnalyseResolution {
    var documentData: [DocumentDataBlock] = []
    
    public func getTextValue(by fieldName: String) -> String? {
        let block = documentData.first { (block) -> Bool in
            return block.fieldName == fieldName
        }
        return block?.visual ?? block?.mrz
    }
}

struct DocumentDataBlock {
    let fieldName : String
    let visual : String?
    let mrz : String?
}


@available(iOS 11.0, *)
public enum AnalyseResolutionStatus: String {
    case initial            = "INITIAL"
    case processing         = "PROCESSING"
    case failed             = "FAILED"
    case finished           = "FINISHED"
    case declined           = "DECLINED"
    case success            = "SUCCESS"
    case operatorRequired   = "OPERATOR_REQUIRED"
}

@available(iOS 11.0, *)
public enum ScenarioState {
    case addToFolder, addAnalyses, waitAnalisesResult
}

@available(iOS 11.0, *)
public enum OZLocalizationCode: String {
    case ru, en, hy
}
