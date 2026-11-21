import AppKit
import AVFoundation

/// The frontend owns presentation and physical controls. Futari's board, memory,
/// resource formats and compiled functions stay behind the C game adapter.
final class FutariView: NSView {
    var game: FutariGame?
    var controls = MacControls()
    var timer: Timer?
    var image: CGImage?
    var pixels = [UInt8](repeating: 0, count: 240 * 320 * 4)
    var paused = false, menuOpen = false, muted = false, filtered = false
    var menuIndex = 0, failure: String?
    var customOptions=CustomGameOptions(), hideHUD=false, invincible=false
    var exploration=false, menuWasPaused=false, rewinding=false, shiftHeld=false,fastHeld=false
    var menuScroll:CGFloat=0, smoothFilteringOverride:Bool?=nil
    var playbackRate:Double {fastHeld ? 4:customOptions.speed}
    let visuals=FutariVisuals()
    var audioPhase=0.0
    let headless:Bool
    let audioEngine = AVAudioEngine(), player = AVAudioPlayerNode()
    let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    var audioReady = false
    var lastTime = ProcessInfo.processInfo.systemUptime, accumulator = 0.0
    let interval = 106634.0 / 6400000.0
    let settings: URL
    let resources: URL
    var testSwitchFrames = 0

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    init(resources: URL, settings: URL, headless:Bool=false) {
        self.headless=headless
        self.resources = resources; self.settings = settings
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
        wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        createGame()
        if headless {return}
        audioEngine.attach(player)
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
        do { try audioEngine.start(); player.play(); audioReady = true }
        catch { NSLog("Futari audio unavailable: %@", String(describing: error)) }
        timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(lostFocus), name: NSWindow.didResignKeyNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("Unsupported initializer") }
    deinit { timer?.invalidate(); if let game { futari_destroy(game) } }

    func createGame() {
        if let game { _ = futari_save_settings(game); futari_destroy(game) }
        game = resources.path.withCString { resourcePath in
            settings.path.withCString { futari_create(resourcePath, $0) }
        }
        applyCustomOptions()
        visuals.clear()
        failure = game == nil ? String(cString: futari_error(nil)) : nil
        controls.clear(); accumulator = 0; lastTime = ProcessInfo.processInfo.systemUptime
        player.stop(); if audioReady { player.play() }
    }
    @objc func lostFocus(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        controls.clear();shiftHeld=false;fastHeld=false;rewinding=false;syncAudio()
    }
    func save() { if let game { _ = futari_save_settings(game) } }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(0.1, now - lastTime); lastTime = now
        advanceTime(elapsed)
    }
    func advanceTime(_ elapsed:Double) {
        guard let game, failure == nil, !paused, !menuOpen else { accumulator = 0; return }
        accumulator += elapsed * (rewinding ? 2:playbackRate)
        if rewinding {
            var steps=0
            while accumulator>=interval && steps<24 {
                if futari_rewind(game,1)==0 {rewinding=false;paused=true;break}
                accumulator-=interval;steps+=1
            }
            refreshImage();return
        }
        var advanced = false
        if futari_scene(game) == 0 {
            // Run the original power-on checks quickly, presenting their progress.
            // Gameplay and all selectable menus retain the board's frame rate.
            for _ in 0..<24 {
                if futari_frame(game,255,255)==0 { failure = String(cString:futari_error(game)); break }
                advanced = true
                if futari_scene(game) != 0 { break }
            }
            accumulator = 0
        }
        var steps=0
        while accumulator >= interval && steps<24 {
            steps+=1
            futari_boost(game,shiftHeld && customOptions.explorationBoost ? 1:0)
            let ports = FutariInputPorts(controls.nextFrame())
            if futari_frame(game, ports.c, ports.d) == 0 {
                failure = String(cString: futari_error(game)); break
            }
            if testSwitchFrames > 0 {
                testSwitchFrames -= 1
                if testSwitchFrames == 0 { futari_test_switch(game, 0) }
            }
            queueAudio(game)
            accumulator -= interval; advanced = true
        }
        if advanced { refreshImage() }
    }
    func refreshImage() {
        guard let game else{return}
        let playing=futari_scene(game)==3
        let width=playing && customOptions.horizontal ? 304:240
        let height=playing && customOptions.expandTallScreens ? min(384,max(320,Int(bounds.height/max(1,bounds.width/CGFloat(width))))):320
        let custom=customOptions.art.active || customOptions.trailStyle != .off || customOptions.background != .art || hideHUD || width != 240 || height != 320 || futari_custom_status(game).worlds>1
        let bitmap:ArtBitmap
        if custom {
            bitmap=visuals.render(game,options:customOptions,hideHUD:hideHUD,rewinding:rewinding,width:width,height:height)
        } else {
            futari_pixels(game,&pixels)
            bitmap=ArtBitmap(width:240,height:320,pixels:stride(from:0,to:pixels.count,by:4).map{i in UInt32(pixels[i])|UInt32(pixels[i+1])<<8|UInt32(pixels[i+2])<<16|0xff000000})
        }
        let data=bitmap.pixels.withUnsafeBytes{Data($0)}
        if let provider=CGDataProvider(data:data as CFData) {
            image=CGImage(width:bitmap.width,height:bitmap.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:bitmap.width*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
        }
        needsDisplay=true
    }
    func queueAudio(_ game: FutariGame) {
        guard audioReady else { return }
        var count: UInt32 = 0
        guard let source = futari_audio(game, &count), count > 0 else {return}
        let samples=resampleAudio(source,count:Int(count),rate:playbackRate)
        guard !samples.isEmpty, let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count)) else{return}
        buffer.frameLength=AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {buffer.floatChannelData![0].update(from:$0.baseAddress!,count:$0.count)}
        player.scheduleBuffer(buffer)
    }
    func resampleAudio(_ source:UnsafePointer<Float>,count:Int,rate:Double)->[Float] {
        var samples=[Float]();samples.reserveCapacity(Int(Double(count)/rate)+2)
        while audioPhase<Double(count) {
            let i=Int(audioPhase),fraction=Float(audioPhase-Double(i))
            samples.append(source[i]*(1-fraction)+source[min(i+1,Int(count)-1)]*fraction)
            audioPhase+=rate
        }
        audioPhase-=Double(count)
        return samples
    }
    override func keyDown(with event: NSEvent) {
        if menuOpen {
            if [126,13].contains(event.keyCode) {moveMenu(-1)}
            else if [125,1].contains(event.keyCode) {moveMenu(1)}
            else if [123,0].contains(event.keyCode) {activateMenu(direction:-1)}
            else if [124,2,36,38,49].contains(event.keyCode) && !event.isARepeat {activateMenu(direction:1)}
            else if [48,53].contains(event.keyCode) && !event.isARepeat {setMenu(false)}
            needsDisplay=true;return
        }
        if event.keyCode==14,let game,futari_scene(game)==3 {if !fastHeld {fastHeld=true;syncAudio()};return}
        if event.keyCode==12 {
            if !event.isARepeat,let game,futari_custom_status(game).rewind_frames>0 {rewinding=true;paused=false;controls.clear();syncAudio()}
            return
        }
        if !event.isARepeat,let game,futari_scene(game)==3 {
            if event.keyCode==34 {activateMenu(.invincibility);return}
            if [27,78].contains(event.keyCode) {activateMenu(.background);return}
            if [24,69].contains(event.keyCode) {activateMenu(.hud);return}
        }
        if let command = controls.keyDown(event.keyCode, isRepeat: event.isARepeat) {
            switch command {
            case .pause: rewinding=false;paused.toggle(); syncAudio()
            case .menu: setMenu(true)
            case .mute: muted.toggle(); player.volume = muted ? 0 : 1
            case .filtering: filtered.toggle();smoothFilteringOverride=filtered
            case .title: restoreRun(title: true)
            case .restart: restoreRun(title: false)
            }
        }
        needsDisplay = true
    }
    override func flagsChanged(with event:NSEvent) {shiftHeld=event.modifierFlags.contains(.shift)}
    override func scrollWheel(with event:NSEvent) {
        if menuOpen {menuScroll-=event.scrollingDeltaY*(event.hasPreciseScrollingDeltas ? 1:12);clampMenuScroll();needsDisplay=true}
        else {super.scrollWheel(with:event)}
    }
    override func mouseDown(with event:NSEvent) {
        guard menuOpen else{return}
        let p=convert(event.locationInWindow,from:nil)
        if !menuPanel.contains(p) {setMenu(false);return}
        if p.x<=menuPanel.width && p.y>=42 && p.y<menuListBottom {
            for (i,y) in menuRowPositions.enumerated() where p.y>=y-menuScroll && p.y<y-menuScroll+28 {
                menuIndex=i;activateMenu(direction:event.modifierFlags.contains(.shift) ? -1:1);break
            }
        }
    }
    override func keyUp(with event: NSEvent) {
        controls.keyUp(event.keyCode)
        if event.keyCode==14 {fastHeld=false;syncAudio()}
        if event.keyCode==12 && rewinding {rewinding=false;syncAudio();refreshImage()}
    }
    func syncAudio() {player.stop();audioPhase=0;if !paused && !menuOpen && !rewinding && audioReady {player.play()}}
    func restoreRun(title: Bool, stage: Bool = false) {
        let restored = game.map { title ? futari_title($0) : stage ? futari_restart_stage($0) : futari_restart($0) } ?? 0
        if restored == 0 { createGame() }
        failure = nil; paused = false;rewinding=false;fastHeld=false;shiftHeld=false;visuals.clear(); controls.clear(); accumulator = 0
        lastTime = ProcessInfo.processInfo.systemUptime; syncAudio()
    }
    func setMenu(_ open: Bool) {
        guard menuOpen != open else{return}
        if open {menuWasPaused=paused;rewinding=false;menuOpen=true}
        else {menuOpen=false;paused=menuWasPaused}
        controls.clear();shiftHeld=false;fastHeld=false;accumulator=0;syncAudio();needsDisplay=true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        let canvas=gamePresentationBounds
        let iw=CGFloat(image?.width ?? 240),ih=CGFloat(image?.height ?? 320)
        let scale = min(canvas.width / iw, canvas.height / ih)
        let rect = NSRect(x:canvas.minX+(canvas.width-iw*scale)/2,y:canvas.minY+(canvas.height-ih*scale)/2,width:iw*scale,height:ih*scale)
        if let image, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState(); context.interpolationQuality = (smoothFilteringOverride ?? (ih>320)) ? .low : .none
            context.clip(to: rect)
            context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1,y: -1)
            let zoom: CGFloat = controls.zoomHeld && customOptions.chargeCameraZoom ? 2 : 1
            context.draw(image,in: NSRect(x:rect.width*(1-zoom)/2,y:rect.height*(1-zoom)/2,width:rect.width*zoom,height:rect.height*zoom)); context.restoreGState()
        }
        if let failure {
            NSColor.black.withAlphaComponent(0.82).setFill();bounds.fill();text("Futari stopped",y:100,size:26);text(failure,y:155,size:14)
        } else if menuOpen {drawCustomMenu()}
        else if paused {text("Paused",y:bounds.midY-20,size:28)}
        else if rewinding {text("Rewinding 2x - Tab to stop",y:bounds.height-40,size:14)}
    }
    func text(_ string: String,y: CGFloat,size: CGFloat) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (string as NSString).draw(in: NSRect(x: 16,y: y,width: bounds.width-32,height: 70),
                                 withAttributes: [.font:NSFont.systemFont(ofSize:size),.foregroundColor:NSColor.white,.paragraphStyle:style])
    }
}

@main final class FutariApplication: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: FutariView!
    static func main() {
        if let index=CommandLine.arguments.firstIndex(of:"--verify-menu"),CommandLine.arguments.count>index+2 {
            do {try verifyFutariMenu(resources:Bundle.main.resourceURL!,inputs:URL(fileURLWithPath:CommandLine.arguments[index+1]),folder:URL(fileURLWithPath:CommandLine.arguments[index+2]))}
            catch {fputs("Menu verification failed: \(error)\n",stderr);exit(1)}
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            let resources = Bundle.main.resourceURL!
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("mushi-diagnostic-settings.bin").path
            guard let game = resources.path.withCString({ r in path.withCString { futari_create(r,$0) } }) else {
                fputs(String(cString:futari_error(nil))+"\n",stderr); exit(1)
            }
            defer { futari_destroy(game) }
            for _ in 0..<120 {
                if futari_frame(game,255,255)==0 { fputs(String(cString:futari_error(game))+"\n",stderr); exit(1) }
            }
            print("Native ARM64 startup passed: 120 frames; no window, audio device, or external runtime opened.")
            return
        }
        let app = NSApplication.shared
        let delegate = FutariApplication(); app.delegate = delegate
        app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Mushi/Native")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            view = FutariView(resources: Bundle.main.resourceURL!,settings: support.appendingPathComponent("settings.bin"))
            window = NSWindow(contentRect: view.frame, styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
            window.title = "Mushihimesama Futari"; window.contentView = view; window.minSize = NSSize(width:320,height:360)
            window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
            let main = NSMenu(); let item = NSMenuItem(); let menu = NSMenu()
            menu.addItem(withTitle:"Quit Futari",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
            item.submenu = menu;main.addItem(item);NSApp.mainMenu = main
            let viewItem = NSMenuItem(); let viewMenu = NSMenu(title: "View")
            let fullscreen = NSMenuItem(title: "Toggle Fullscreen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            fullscreen.keyEquivalentModifierMask = [.command,.control]; fullscreen.target = window
            viewMenu.addItem(fullscreen);viewItem.submenu = viewMenu; main.addItem(viewItem)
            NSApp.activate(ignoringOtherApps: true)
        } catch { NSLog("Futari startup failed: %@",String(describing:error)); NSApp.terminate(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { view?.save() }
}
