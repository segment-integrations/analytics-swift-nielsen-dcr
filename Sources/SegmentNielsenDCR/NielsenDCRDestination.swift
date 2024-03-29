//
//  NielsenDCRDestination.swift
//  NielsenDCRDestination
//
//  Created by Cody Garvin on 9/13/21.

// MIT License
//
// Copyright (c) 2021 Segment
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import Segment
import NielsenAppApi
import AVKit

@objc(SEGNielsenDCRDestination)
public class ObjCSegmentNielsenDCR: NSObject, ObjCPlugin, ObjCPluginShim {
    public func instance() -> EventPlugin { return NielsenDCRDestination() }
}

public class NielsenDCRDestination: DestinationPlugin {
    public let timeline = Timeline()
    public let type = PluginType.destination
    public let key = "Nielsen DCR"
    public var analytics: Analytics? = nil
    
    private var nielsenSettings: NielsenSettings?
    
    private let avPlayerViewController = AVPlayerViewController()
    private var avPlayer:AVPlayer?
    private var nielsenAppApi: NielsenAppApi!
    private var defaultSettings: Settings!
    private var startingPlayheadPosition: Int64!
    private var playheadTimer: Timer!
        
    public init() { }

    public func update(settings: Settings, type: UpdateType) {
        // Skip if you have a singleton and don't want to keep updating via settings.
        guard type == .initial else { return }
        
        // Grab the settings and assign them for potential later usage.
        // Note: Since integrationSettings is generic, strongly type the variable.
        guard let tempSettings: NielsenSettings = settings.integrationSettings(forPlugin: self) else { return }
        nielsenSettings = tempSettings
        defaultSettings = settings
        nielsenAppApi = NielsenAppApi(appInfo: tempSettings.appId, delegate: nil)
    }
    
    public func track(event: TrackEvent) -> TrackEvent? {
        
        if let options = event.integrations?.dictionaryValue?[key] as? [String: Any],
           let properties = event.properties?.dictionaryValue {
            trackPlayBackEvents(event: event, options: options, properties: properties)
        }
    
        return event
    }
    
    public func screen(event: ScreenEvent) -> ScreenEvent? {
        let options = event.integrations?.dictionaryValue?[key] as? [String : Any] ?? nil
        let properties = event.properties?.dictionaryValue ?? [:]
        let metaData: [String: Any] = [
            "type" : "static",
            "assetid" : returnCustomContentAssetId(properties: properties, defaultKey: "asset_id"),
            "section" : returnCustomSectionProperty(properties: properties, defaultKey: event.name ?? ""),
            "segA" : (options != nil) ? options?["segA"] ?? "" : "",
            "segB" : (options != nil) ? options?["segB"] ?? "" : "",
            "segC" : (options != nil) ? options?["segC"] ?? "" : "",
            "crossId1" : (options != nil) ? options?["crossId1"] ?? "" : ""
        ]
        
        nielsenAppApi.loadMetadata(metaData)
        return event
    }
}

private extension NielsenDCRDestination {
    
    func returnMappedAdProperties(properties: [String: Any], options: [String: Any])-> [String: Any] {
        let adMetadata: [String: Any] = [
            "assetid": returnCustomAdAssetId(properties: properties, defaultKey: "asset_id"),
            "type": properties["type"] as? String ?? "ad",
            "title": properties["title"] as? String ?? ""
        ]
        var mutableAdMetadata = adMetadata
        
        if properties["type"] as? String == "pre-roll" {
            mutableAdMetadata["type"] = "preroll"
        }
        
        if properties["type"] as? String == "mid-roll" {
            mutableAdMetadata["type"] = "midroll"
        }
        
        if properties["type"] as? String == "post-roll" {
            mutableAdMetadata["type"] = "postroll"
        }
        
        return coerceToString(map: mutableAdMetadata)
    }
    
    func returnCustomAdAssetId(properties: [String: Any], defaultKey: String)-> String {
        let customKey = nielsenSettings?.adAssetIdPropertyName ?? ""
        var value = ""
        let customAssetId = properties[customKey] as? String
        if (customKey.count > 0) && (customAssetId != nil) {
            value = properties[customKey] as? String ?? ""
        } else if properties[defaultKey] != nil {
            value = properties[defaultKey] as? String ?? ""
        } else{
            value = ""
        }
        
        return value
    }
    
    func returnCustomContentAssetId(properties: [String: Any], defaultKey: String) -> String {
        var value = ""
        let customKey = nielsenSettings?.contentAssetIdPropertyName ?? ""
        let customContentAssetId = properties[customKey] as? String
        if customKey.count > 0 && (customContentAssetId != nil) {
            value = properties[customKey] as? String ?? ""
        } else if properties[defaultKey] != nil {
            value = properties[defaultKey] as? String ?? ""
        } else {
            value = ""
        }
        
        return value
    }
    
    func returnCustomSectionProperty(properties: [String: Any], defaultKey: String) -> String {
        var value = ""
        let customKey = nielsenSettings?.customSectionProperty ?? ""
        let customSectionName = properties[customKey] as? String
        if customKey.count > 0 && (customSectionName != nil) {
            value = properties[customKey] as? String ?? ""
        } else if defaultKey != "" {
            value = defaultKey
        } else {
            value = "Unknown"
        }
            
        return value
    }
    
    func returnFullEpisodeStatus(src: [String: Any], key: String)-> String {
        let value = src[key] as? Bool
        if value == true {
            return "y"
        }
        
        return "n"
    }
    
    func returnAdLoadType(options: [String: Any], properties: [String: Any])->String {
        var value = ""
        if (options["adLoadType"] != nil) {
            value = options["adLoadType"] as? String ?? ""
        } else if properties["loadType"] != nil {
            value = properties["loadType"] as? String ?? ""
        } else if properties["load_type"] != nil {
            value = properties["load_type"] as? String ?? ""
        }
        
        if value == "dynamic" {
            return "2"
        }
        
        return "1"
    }
    
    func returnHasAdsStatus(src: [String: Any], key: String)->String {
        let value = src[key] as? Bool
        if value == true {
            return "1"
        }
        
        return "0"
    }

    func returnContentLength(src: [String: Any], defaultKey: String)-> String {
        let contentLengthKey = nielsenSettings?.contentLengthPropertyName ?? ""
        var contentLength = ""
        let customContentLength = src[contentLengthKey]
        if (contentLengthKey.count > 0) && (customContentLength != nil) {
            contentLength = src[contentLengthKey] as? String ?? ""
        } else if (src["total_length"] != nil) {
            contentLength = src["total_length"] as? String ?? ""
        } else {
            contentLength = ""
        }
        
        return contentLength
    }
    
    func returnAirdate(properties: [String: Any], defaultKey: String)-> String {
        let dateSTR = properties[defaultKey] as? String
        let dateArrayISO: [String] = dateSTR?.components(separatedBy: "T") ?? []
        let dateArraySimpleDate: [String] = dateSTR?.components(separatedBy: "-") ?? []
        var date: Date!
        //Convert the string date if it was passed in ISO 8601 format ie. 2019-08-30T21:00:00Z
        if dateArrayISO.count > 1 {
            let dateFormatter = ISO8601DateFormatter()
            date = dateFormatter.date(from: dateSTR ?? "")
        }
        //Convert the string date if it was passed in simple date format ie. 2019-08-30
        if dateArraySimpleDate.count > 2 && dateSTR?.count == 10 {
            let simpleDateFormatter = DateFormatter()
            simpleDateFormatter.dateFormat = "yyyy-MM-dd"
            simpleDateFormatter.timeZone = TimeZone(identifier: "UTC")
            date = simpleDateFormatter.date(from: dateSTR ?? "")
        }
        //Manipulate the date to Nielsen format
        let nielsenDateFormatter = DateFormatter()
        nielsenDateFormatter.timeZone = TimeZone(identifier: "UTC")
        nielsenDateFormatter.dateFormat = "yyyyMMdd HH:mm:ss"
        let nielsenDateString = nielsenDateFormatter.string(from: date)
        
        if nielsenDateString.count > 0 {
            return nielsenDateString
        } else if dateSTR != "" {
            return dateSTR ?? ""
        } else{
            return ""
        }
    }
    
    func returnMappedContentProperties(properties: [String: Any], options: [String: Any]) -> [String: Any] {
        let contentMetadata: [String: Any] = [
            "pipmode" : options["pipmode"] ?? "false",
            "adloadtype" : returnAdLoadType(options: options, properties: properties),
            "assetid" : returnCustomContentAssetId(properties: properties, defaultKey: "asset_id"),
            "type" : "content",
            "segB" : options["segB"] ?? "",
            "segC" : options["segC"] ?? "",
            "title" : properties["title"] ?? "",
            "program" : properties["program"] ?? "",
            "isfullepisode" : returnFullEpisodeStatus(src: properties, key: "full_episode"),
            "hasAds" : returnHasAdsStatus(src: options, key: "hasAds"),
            "airdate" : returnAirdate(properties: properties, defaultKey: "airdate"),
            "length" : returnContentLength(src: properties, defaultKey: "content_length"),
            "crossId1" : options["crossId1"] ?? "",
            "crossId2" : options["crossId2"] ?? ""
        ]
        
        var mutableContentMetadata: [String: Any] = contentMetadata
        if (nielsenSettings?.subbrandPropertyName != nil) {
            let subbrandValue = properties[nielsenSettings?.subbrandPropertyName ?? ""]
            mutableContentMetadata["subbrand"] = subbrandValue
        }

        if (nielsenSettings?.clientIdPropertyName != nil) {
            let clientIdValue = properties[nielsenSettings?.clientIdPropertyName ?? ""]
            mutableContentMetadata["clientid"] = clientIdValue
        }
        
        return coerceToString(map: mutableContentMetadata)
    }
    
    // Nielsen expects all value type String.
    
    func coerceToString(map: [String: Any])-> [String: Any] {
        var newMap = map
        for (key,_) in map {
            let value = map[key] as? String
            if value != nil {
                newMap[key] = value ?? ""
            }
        }
        
        return newMap
    }
    
    // MARK:- Playback Events
    
    func trackPlayBackEvents(event: TrackEvent, options: [String: Any], properties: [String: Any]) {
        // Nielsen requires we load content metadata and call play upon playback start
        if event.event == "Video Playback Started" {
            let channelInfo: [String: Any] = [
                // channelName is optional for DCR, if not present Nielsen asks to set default
                "channelName" : options["channelName"] as? String ?? "defaultChannelName",
                // if mediaURL is not available, Nielsen expects an empty value
                "mediaURL" : options["mediaUrl"] as? String ?? ""
            ]
            let contentMetadata = returnMappedContentProperties(properties: properties, options: options)
            nielsenAppApi.loadMetadata(contentMetadata)
            startPlayheadTimer(trackEvent: event)
            nielsenAppApi.play(channelInfo)
            return
        }
        
        if event.event == "Video Playback Resumed" ||
            event.event == "Video Playback Seek Completed" ||
            event.event == "Video Playback Buffer Completed" {
            let channelInfo: [String: Any] = [
                // channelName is optional for DCR, if not present Nielsen asks to set default
                "channelName" : options["channelName"] ?? "defaultChannelName",
                // if mediaURL is not available, Nielsen expects an empty value
                "mediaURL" : options["mediaUrl"] ?? ""
            ]
            
            startPlayheadTimer(trackEvent: event)
            nielsenAppApi.play(channelInfo)
            return
        }
        
        if event.event == "Video Playback Paused" ||
            event.event == "Video Playback Seek Started" ||
            event.event == "Video Playback Buffer Started" ||
            event.event == "Video Playback Interrupted" ||
            event.event == "Video Playback Exited" {
            stopPlayheadTimer(trackEvent: event)
            nielsenAppApi.stop()
            return
        }
        
        if event.event == "Video Playback Completed" {
            stopPlayheadTimer(trackEvent: event)
            nielsenAppApi.end()
            return
        }
        
        //Content events
        
        if event.event == "Video Content Started" {
            let contentMetadata = returnMappedContentProperties(properties: properties, options: options)
            nielsenAppApi.loadMetadata(contentMetadata)
            startPlayheadTimer(trackEvent: event)
            return
        }
        
        if event.event == "Video Content Playing" {
            startPlayheadTimer(trackEvent: event)
            return
        }
        
        if event.event == "Video Content Completed" {
            stopPlayheadTimer(trackEvent: event)
            nielsenAppApi.stop()
            return
        }
        
        //Ad events
        
        if event.event == "Video Ad Started" {
            let adMetadata = returnMappedAdProperties(properties: event.properties?.dictionaryValue ?? [:], options: options)
            
            // In case of ad `type` preroll, call `loadMetadata` with metadata values for content, followed by `loadMetadata` with ad (preroll) metadata
            
            if properties["type"] as? String == "pre-roll" {
                guard let contentProperties = properties["content"] as? [String: Any] else {
                    return
                }
                let adContentMetadata = returnMappedContentProperties(properties: contentProperties, options: options)
                nielsenAppApi.loadMetadata(adContentMetadata)
            }
            
            nielsenAppApi.loadMetadata(adMetadata)
            startPlayheadTimer(trackEvent: event)
            return
        }
        
        if event.event == "Video Ad Playing" {
            startPlayheadTimer(trackEvent: event)
            return
        }
        
        if event.event == "Video Ad Completed" {
            stopPlayheadTimer(trackEvent: event)
            nielsenAppApi.stop()
            return
        }
    }

    // MARK: - Timers
    
    func startPlayheadTimer(trackEvent: TrackEvent) {
        DispatchQueue.main.async {
            if self.playheadTimer == nil {
                // Remove 1 from playhead position to maintain original position
                self.startingPlayheadPosition = self.returnPlayheadPosition(trackEvent: trackEvent) - 1
                self.playheadTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.playHeadTimeEvent(timer:)), userInfo: nil, repeats: true)
            }
        }
    }
    
    @objc func playHeadTimeEvent(timer: Timer) {
        startingPlayheadPosition = startingPlayheadPosition + 1
        nielsenAppApi.playheadPosition(startingPlayheadPosition)
    }
    
    func returnPlayheadPosition(trackEvent: TrackEvent)-> Int64 {
        var playheadPosition: Int64 = 0
        // if livestream, you need to send current UTC timestamp
        if trackEvent.properties?.dictionaryValue?["livestream"] as? Bool == true {
            var position: Int64 = 0
            position = trackEvent.properties?.dictionaryValue?["position"] as? Int64 ?? 0
            let currentTime = Int64(Date().timeIntervalSince1970)
            if ((nielsenSettings?.sendCurrentTimeLivestream) != nil) == true {
                //for livestream, if this setting is enabled just send the curent time
                playheadPosition = currentTime
            } else {
                //for livestream, properties.position is a negative integer representing offset in seconds from current time
                playheadPosition = currentTime + position
            }
        } else if ((trackEvent.properties?.dictionaryValue?["position"]) != nil){
            // if position is passed in we should override the state of the counter with the explicit position given from the customer
            playheadPosition = trackEvent.properties?.dictionaryValue?["position"] as? Int64 ?? 0
        }
        
        return playheadPosition
    }
    
    func stopPlayheadTimer(trackEvent: TrackEvent) {
        DispatchQueue.main.async {
            self.nielsenAppApi.playheadPosition(self.startingPlayheadPosition)
            if (self.playheadTimer != nil) {
                self.playheadTimer.invalidate()
                self.playheadTimer = nil
            }
        }
    }
}

extension NielsenDCRDestination: VersionedPlugin {
    public static func version() -> String {
        return __destination_version
    }
}

private struct NielsenSettings: Codable {
    let appId: String
    let contentAssetIdPropertyName: String
    let customSectionProperty: String
    let subbrandPropertyName: String
    let adAssetIdPropertyName: String
    let contentLengthPropertyName: String
    let clientIdPropertyName: String
    let sendCurrentTimeLivestream: String
    let assetIdPropertyName: String
}
