//
//  PreferencesWindowController.swift
//  Aerial
//
//  Created by John Coates on 10/23/15.
//  Copyright © 2015 John Coates. All rights reserved.
//

import Cocoa
import AVKit
import AVFoundation
import ScreenSaver

class TimeOfDay {
    let title: String
    var videos: [AerialVideo] = [AerialVideo]()
    
    init(title: String) {
        self.title = title
    }
    
}

class City {
    var night: TimeOfDay = TimeOfDay(title: "night")
    var day: TimeOfDay = TimeOfDay(title: "day")
    let name: String
    
    init(name: String) {
        self.name = name
    }
    
    func addVideoForTimeOfDay(_ timeOfDay: String, video: AerialVideo) {
        if timeOfDay.lowercased() == "night" {
            video.arrayPosition = night.videos.count
            night.videos.append(video)
        } else {
            video.arrayPosition = day.videos.count
            day.videos.append(video)
        }
    }
}

@objc(PreferencesWindowController)
class PreferencesWindowController: NSWindowController, NSOutlineViewDataSource,
NSOutlineViewDelegate/*, VideoDownloadDelegate*/ {

    @IBOutlet var outlineView: NSOutlineView!
    @IBOutlet var playerView: AVPlayerView!
    @IBOutlet var differentAerialCheckbox: NSButton!
    @IBOutlet var projectPageLink: NSButton!
    @IBOutlet var cacheLocation: NSPathControl!
    @IBOutlet var cacheAerialsAsTheyPlayCheckbox: NSButton!
    
    var player: AVPlayer = AVPlayer()
    
    var videos: [AerialVideo]?
    
    static var loadedJSON: Bool = false
    
    lazy var preferences = Preferences.sharedInstance
    
    // MARK: - Init
    
    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
    }
    override init(window: NSWindow?) {
        super.init(window: window)
        
    }
    
    // MARK: - Lifecycle
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.player.volume = 0
        if let previewPlayer = AerialView.previewPlayer {
            self.player = previewPlayer
        }
        
        outlineView.floatsGroupRows = false
        
        player.volume = 0
        playerView.player = player
        playerView.controlsStyle = .none
        if #available(OSX 10.10, *) {
            playerView.videoGravity = AVLayerVideoGravityResizeAspectFill
        }
        
        if preferences.differentAerialsOnEachDisplay {
            differentAerialCheckbox.state = NSOnState
        }
        
        if !preferences.cacheAerials {
            cacheAerialsAsTheyPlayCheckbox.state = NSOffState
        }
        
        colorizeProjectPageLink()
        
        if let cacheDirectory = VideoCache.cacheDirectory {
            cacheLocation.url = URL(fileURLWithPath: cacheDirectory as String)
        }
        loadVideo()
    }
    
    // MARK: - Setup
    
    fileprivate func colorizeProjectPageLink() {
        let color = NSColor(calibratedRed: 0.18, green: 0.39, blue: 0.76, alpha: 1)
        let link = projectPageLink.attributedTitle
        let coloredLink = NSMutableAttributedString(attributedString: link)
        let fullRange = NSRange(location: 0, length: coloredLink.length)
        coloredLink.addAttribute(NSForegroundColorAttributeName,
                                 value: color,
                                  range: fullRange)
        projectPageLink.attributedTitle = coloredLink
    }
    
    // MARK: - Preferences
    
    @IBAction func cacheAerialsAsTheyPlayClick(_ button: NSButton!) {
        debugLog("cache aerials as they play: \(button.state)")
        
        let onState = (button.state == NSOnState)
        preferences.cacheAerials = onState
    }
    
    @IBAction func userSetCacheLocation(_ button: NSButton?) {
        let openPanel = NSOpenPanel()
        
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Choose Aerial Cache Directory"
        openPanel.prompt = "Choose"
        openPanel.directoryURL = cacheLocation.url
        
        openPanel.begin { result in
            guard result == NSFileHandlingPanelOKButton,
                openPanel.urls.count > 0 else {
                return
            }
            
            let cacheDirectory = openPanel.urls[0]
            self.preferences.customCacheDirectory = cacheDirectory.path
            self.cacheLocation.url = cacheDirectory
        }
    }
    @IBAction func resetCacheLocation(_ button: NSButton?) {
        preferences.customCacheDirectory = nil
        if let cacheDirectory = VideoCache.cacheDirectory {
            cacheLocation.url = URL(fileURLWithPath: cacheDirectory as String)
        }
    }
    
    @IBAction func outlineViewSettingsClick(_ button: NSButton) {
        let menu = NSMenu()
        menu.insertItem(withTitle: "Uncheck All",
            action: #selector(PreferencesWindowController.outlineViewUncheckAll(button:)),
            keyEquivalent: "",
            at: 0)
        
        menu.insertItem(withTitle: "Check All",
            action: #selector(PreferencesWindowController.outlineViewCheckAll(button:)),
            keyEquivalent: "",
            at: 1)
        
        let event = NSApp.currentEvent
        NSMenu.popUpContextMenu(menu, with: event!, for: button)
    }
    
    func outlineViewUncheckAll(button: NSButton) {
        setAllVideos(inRotation: false)
    }
    
    func outlineViewCheckAll(button: NSButton) {
        setAllVideos(inRotation: true)
    }
    
    func setAllVideos(inRotation: Bool) {
        guard let videos = videos else {
            return
        }
        
        for video in videos {
            preferences.setVideo(videoID: video.id,
                                 inRotation: inRotation,
                                 synchronize: false)
        }
        preferences.synchronize()
        
        outlineView.reloadData()
    }
    
    @IBAction func differentAerialsOnEachDisplayCheckClick(_ button: NSButton?) {
        let state = differentAerialCheckbox.state
        let onState = (state == NSOnState)
        
        preferences.differentAerialsOnEachDisplay = onState
        
        debugLog("set differentAerialsOnEachDisplay to \(onState)")
    }
    
    // MARK: - Link
    
    @IBAction func pageProjectClick(_ button: NSButton?) {
        let workspace = NSWorkspace.shared()
        let url = URL(string: "http://github.com/JohnCoates/Aerial")!
        workspace.open(url)
    }
    
    func loadVideo() {
        var videos = [AerialVideo]()
        let documentsUrl = self.cacheLocation.url!;
        
        do {
            // Get the directory contents urls (including subfolders urls)
            let directoryContents = try FileManager.default.contentsOfDirectory(at: documentsUrl, includingPropertiesForKeys: nil, options: [])
            print(directoryContents)
            
            // if you want to filter the directory contents you can do like this:
            let mp3Files = directoryContents.filter{ $0.pathExtension == "mov" }
            print("mp3 urls:",mp3Files)
            let mp3FileNames = mp3Files.map{ $0.deletingPathExtension().lastPathComponent }
            print("mp3 list:", mp3FileNames)
            
        
        for file in mp3Files {
            let name = file.deletingPathExtension().lastPathComponent
            let video = AerialVideo(id: "1", name: name, type: "mov", timeOfDay: "aaa", url: file.path);
            videos.append(video)
        }
        self.videos = videos
        
        DispatchQueue.main.async {
            self.outlineView.reloadData()
            self.outlineView.expandItem(nil, expandChildren: true)
        }
        } catch let error as NSError {
            print(error.localizedDescription)
        }

    }

    @IBAction func close(_ sender: AnyObject?) {
        NSApp.mainWindow?.endSheet(window!)
    }
    
    // MARK: - Outline View Delegate & Data Source
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let videos = self.videos {
            return videos.count
        }
        else{
            return 0
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            return false
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            if let videos = self.videos {
                return videos[index]}
            else{
                return false
            }
        }
            return false
    }
    
    func outlineView(_ outlineView: NSOutlineView,
                     objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        if let video = item as? AerialVideo {
            return video.name;
        }
        return "untitled"
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldEdit tableColumn: NSTableColumn?, item: Any) -> Bool {
        return false
    }
    
    func outlineView(_ outlineView: NSOutlineView, dataCellFor tableColumn: NSTableColumn?, item: Any) -> NSCell? {
        let row = outlineView.row(forItem: item)
        return tableColumn!.dataCell(forRow: row) as? NSCell
    }
    
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            return false
    }

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        switch item {
        case is AerialVideo:
            let video = item as! AerialVideo
            let view = outlineView.make(withIdentifier: "CheckCell",
                                        owner: self) as! CheckCellView
            view.textField?.stringValue = video.name
            
            let isInRotation = preferences.videoIsInRotation(videoID: video.id)
            
            if isInRotation {
                view.checkButton.state = NSOnState
            } else {
                view.checkButton.state = NSOffState
            }
            
            view.onCheck = { checked in
                self.preferences.setVideo(videoID: video.id,
                                          inRotation: checked)
            }
            return view
        default:
            return nil
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        switch item {
        case is AerialVideo:
            player = AVPlayer()
            player.volume = 0
            playerView.player = player
            
            let video = item as! AerialVideo
            
            let asset = CachedOrCachingAsset(video.url)
            
            let item = AVPlayerItem(asset: asset)
            
            player.replaceCurrentItem(with: item)
            player.play()
            
            return true
        default:
            return false
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            return 18
    }
}
