//
//  OZFileVideoManager.swift
//  OZLiveness
//
//  Created by Igor Ovchinnikov on 22/07/2019.
//  Copyright © 2019 Igor Ovchinnikov. All rights reserved.
//

import Foundation
import AVFoundation

class OZFileVideoManager {
    
    private init() { }
    
    private static let extention = "mp4"
    
    static var directoryURL : URL? = {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let paths = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        for filePath in (paths ?? []) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(filePath))
        }
        return directory
    }()
    
    class func cleanTempDirectory() {
        if let directoryURL = directoryURL {
            let paths = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
            for filePath in (paths ?? []) {
                try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(filePath))
            }
        }
    }
    
    class var newVideoURL : URL? {
        get {
            guard let directoryURL = self.directoryURL
                else { return nil }
            let fileName = UUID().uuidString + "." +  extention
            let newVideoURL = directoryURL.appendingPathComponent(fileName)
            return newVideoURL
        }
    }
    
    class func deleteFile(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    class func cropVideo(url: URL, endOffset: Float, completion: @escaping (_ url : URL?) -> Void) {

        let asset = AVAsset(url: url)
        let length = Float(asset.duration.value) / Float(asset.duration.timescale)
        if length > endOffset, let outputURL = OZFileVideoManager.newVideoURL {
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {return}
            exportSession.outputURL = outputURL
            exportSession.outputFileType = AVFileType.mp4
            
            let startTime = CMTime(seconds: Double(length - endOffset), preferredTimescale: 1000)
            let endTime = CMTime(seconds: Double(length), preferredTimescale: 1000)
            let timeRange = CMTimeRange(start: startTime, end: endTime)
            
            exportSession.timeRange = timeRange
            exportSession.exportAsynchronously {
                DispatchQueue.main.async {
                    completion(outputURL)
                }
            }
        }
        else {
            DispatchQueue.main.async {
                completion(url)
            }
        }
    }
}
