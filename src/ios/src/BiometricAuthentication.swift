import UIKit
import Firebase
import OZLivenessSDK

var isFirebaseConfigured = false

enum BiometricAuthenticationError: Error {
    case credentialsNotProvided
}

struct Credentials {
    var apiUrl: String
    var username: String
    var password: String
    
    init(settings: [AnyHashable: Any]) {
        apiUrl = settings["api_url"] as! String
        username = settings["username"] as! String
        password = settings["password"] as! String
    }
}


@objc(BiometricAuthentication)
class BiometricAuthentication : CDVPlugin {
    
    private var credentials: Credentials!
    private var currentCommand: CDVInvokedUrlCommand!
    private var base64ImageString: String = String()
    
    private lazy var documentImageUrl: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        var documentDirectoryUrl = paths[0]
        documentDirectoryUrl.appendPathComponent("doc.png")
        return documentDirectoryUrl
    }()
    
    private var rootViewController: UIViewController? {
        let window = UIApplication.shared.keyWindow
        return window?.rootViewController
    }
    
    @objc(analyze:)
    func analyze(_ command: CDVInvokedUrlCommand) {
        initialize(command: command)
        presentLiveness()
    }
    
    
    
    private func initialize(command: CDVInvokedUrlCommand) {
        configureSdkSettings(command)
        configureFirebaseIfNeeded()
        login { (result) in
            print(result)
        }
    }
    
    private func configureSdkSettings(_ command: CDVInvokedUrlCommand) {
        print(#function, "Arguments: \(command.arguments)")
        currentCommand = command
        OZSDK.attemptSettings = OZAttemptSettings(singleCount: 2, commonCount: 3)
        credentials = Credentials(settings: commandDelegate.settings)
        OZSDK.host = credentials.apiUrl
        saveDocumentImage(command)
        configureSDKLocale(command)
    }

    private func saveDocumentImage(_ command: CDVInvokedUrlCommand) {
        if command.arguments.count > 0 {
            base64ImageString = command.argument(at: 0) as? String ?? ""
            saveImageData(base64EncodedString: base64ImageString)
        }
    }
    private func configureSDKLocale(_ command: CDVInvokedUrlCommand) {
        var locale = "en"
        if command.arguments.count > 1 {
            locale = command.argument(at: 1) as! String
        }
        switch locale {
        case "ru":
            OZSDK.localizationCode = OZLocalizationCode.ru
        case "hy":
            OZSDK.localizationCode = OZLocalizationCode.hy
        default:
            OZSDK.localizationCode = OZLocalizationCode.en
        }
    }
    
    private func presentLiveness() {
        let actions = [OZVerificationMovement.smile, OZVerificationMovement.scanning]
        let livenessViewController = OZSDK.createVerificationVCWithDelegate(self, actions: actions)
        self.rootViewController?.present(livenessViewController, animated: true)
    }
    
    private func configureFirebaseIfNeeded() {
        if (isFirebaseConfigured == false) {
            FirebaseApp.configure()
            isFirebaseConfigured.toggle()
        }
    }
    
    private func saveImageData(base64EncodedString: String) {
        let data = Data(base64Encoded: base64EncodedString, options: .init(rawValue: 0))
        do {
            try data?.write(to: documentImageUrl, options: .atomic)
        } catch {
            print(error)
        }
    }
    

    private func login(completionHandler:  Optional<(Result<String, Error>)->Void> = nil) {
        // Check for existing auth token
        if let authToken = OZSDK.authToken {
            completionHandler?(.success(authToken))
            return
        }
        // Log in
        let username = credentials.username
        let password = credentials.password
        OZSDK.login(username, password: password) { (authToken, error) in
            guard let authToken = authToken, error == nil else {
                completionHandler?(.failure(error!))
                return
            }
            OZSDK.authToken = authToken
            completionHandler?(.success(authToken))
        }
    }
}

// MARK: - OZVerificationDelegate

extension BiometricAuthentication: OZVerificationDelegate {
    
    private func sendNoResultCommand() {
        let result = CDVPluginResult(status: .error)
        let callbackId = currentCommand.callbackId
        commandDelegate.send(result, callbackId: callbackId)
    }
    
    private func documentAnalyze(documentPhoto: DocumentPhoto, results: [OZVerificationResult], analyseStates: Set<OZAnalysesState>) {
        OZSDK.documentAnalyse(documentPhoto: documentPhoto, results: results, analyseStates: analyseStates, scenarioState: { (scenarioState) in
            print("scenarioState: \(scenarioState)")
        }, fileUploadProgress: { (progress) in
            print("Progress: \(progress)")
        }) { (analyseResolutionStatus, analyseResolutions, error) in
            print("analyseResolutionStatus: \(analyseResolutionStatus) analyseResolutions: \(analyseResolutions), error: \(error)")
          
            if let analyseResolutionStatus = analyseResolutionStatus {
                switch analyseResolutionStatus {
                case .initial, .processing:
                    break
                case .success, .finished, .operatorRequired, .failed:
                    self.commandDelegate.send(CDVPluginResult(status: .ok, messageAs:  analyseResolutions?.first?.folderID), callbackId: self.currentCommand.callbackId)
                    print("Finished with results:\(analyseResolutions)")
                case .declined:
                    self.sendNoResultCommand()
                }
            } else if let error = error {
                self.sendNoResultCommand()
            }
        }
    }
    
    func onOZVerificationResult(results: [OZVerificationResult]) {
        print(#function, "results: \(results)")
        
        let analyseResults = results.filter({
            $0.status == .userProcessedSuccessfully
        })
        
        if analyseResults.isEmpty {
            sendNoResultCommand()
            return
        }
        
        login { (result) in
            switch result {
            case .success:
                let documentPhoto = DocumentPhoto(front: self.documentImageUrl, back: nil)
                self.documentAnalyze(
                    documentPhoto: documentPhoto,
                    results: analyseResults,
                    analyseStates: [.quality]
                )
            case .failure:
                self.sendNoResultCommand()
            }
        }
    }
}
