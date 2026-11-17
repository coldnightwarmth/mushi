import AppKit
import AVFoundation

/// The frontend owns presentation and physical controls. Futari's board, memory,
/// resource formats and compiled functions stay behind the C game adapter.
final class FutariView: NSView {
    private var game: FutariGame?
    private var controls = MacControls()
    private var timer: Timer?
    private var image: CGImage?
    private var pixels = [UInt8](repeating: 0, count: 240 * 320 * 4)
    private var paused = false, menuOpen = false, muted = false, filtered = false
    private var menuIndex = 0, failure: String?
    private let audioEngine = AVAudioEngine(), player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    private var audioReady = false
    private var lastTime = ProcessInfo.processInfo.systemUptime, accumulator = 0.0
    private let interval = 106634.0 / 6400000.0
    private let settings: URL
    private let resources: URL
    private var testSwitchFrames = 0

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    init(resources: URL, settings: URL) {
        self.resources = resources; self.settings = settings
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
        wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        createGame()
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

    private func createGame() {
        if let game { _ = futari_save_settings(game); futari_destroy(game) }
        game = resources.path.withCString { resourcePath in
            settings.path.withCString { futari_create(resourcePath, $0) }
        }
        failure = game == nil ? String(cString: futari_error(nil)) : nil
        controls.clear(); accumulator = 0; lastTime = ProcessInfo.processInfo.systemUptime
        player.stop(); if audioReady { player.play() }
    }
    @objc private func lostFocus(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        controls.clear()
    }
    func save() { if let game { _ = futari_save_settings(game) } }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(0.1, now - lastTime); lastTime = now
        guard let game, failure == nil, !paused, !menuOpen else { accumulator = 0; return }
        accumulator += elapsed
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
        while accumulator >= interval {
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
        if advanced {
            futari_pixels(game, &pixels)
            let data = Data(pixels)
            if let provider = CGDataProvider(data: data as CFData) {
                image = CGImage(width: 240, height: 320, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: 960, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            }
            needsDisplay = true
        }
    }
    private func queueAudio(_ game: FutariGame) {
        guard audioReady else { return }
        var count: UInt32 = 0
        guard let source = futari_audio(game, &count), count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return }
        buffer.frameLength = count
        buffer.floatChannelData![0].update(from: source, count: Int(count))
        player.scheduleBuffer(buffer)
    }
    override func keyDown(with event: NSEvent) {
        if menuOpen {
            if [126,13].contains(event.keyCode) { menuIndex = (menuIndex + menuItems.count - 1) % menuItems.count }
            else if [125,1].contains(event.keyCode) { menuIndex = (menuIndex + 1) % menuItems.count }
            else if [36,38].contains(event.keyCode) && !event.isARepeat { chooseMenu() }
            else if [48,53].contains(event.keyCode) && !event.isARepeat { setMenu(false) }
            needsDisplay = true; return
        }
        if let command = controls.keyDown(event.keyCode, isRepeat: event.isARepeat) {
            switch command {
            case .pause: paused.toggle(); syncAudio()
            case .menu: setMenu(true)
            case .mute: muted.toggle(); player.volume = muted ? 0 : 1
            case .filtering: filtered.toggle()
            case .title: restoreRun(title: true)
            case .restart: restoreRun(title: false)
            }
        }
        needsDisplay = true
    }
    override func keyUp(with event: NSEvent) { controls.keyUp(event.keyCode) }
    private func syncAudio() { player.stop(); if !paused && !menuOpen && audioReady { player.play() } }
    private func restoreRun(title: Bool) {
        let restored = game.map { title ? futari_title($0) : futari_restart($0) } ?? 0
        if restored == 0 { createGame() }
        failure = nil; paused = false; controls.clear(); accumulator = 0
        lastTime = ProcessInfo.processInfo.systemUptime; syncAudio()
    }
    private func setMenu(_ open: Bool) { menuOpen = open; controls.clear(); accumulator = 0; syncAudio(); needsDisplay = true }
    private var menuItems: [String] {
        ["Resume", "Restart game", "Return to title", muted ? "Sound: off" : "Sound: on",
         filtered ? "Filtering: smooth" : "Filtering: pixel", "Toggle fullscreen", "Operator settings"]
    }
    private func chooseMenu() {
        switch menuIndex {
        case 0: paused = false; setMenu(false)
        case 1: restoreRun(title: false); setMenu(false)
        case 2: restoreRun(title: true); setMenu(false)
        case 3: muted.toggle(); player.volume = muted ? 0 : 1
        case 4: filtered.toggle()
        case 5: window?.toggleFullScreen(nil)
        case 6: if let game { futari_test_switch(game,1); testSwitchFrames = 180 }; paused = false; setMenu(false)
        default: break
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        let scale = min(bounds.width / 240, bounds.height / 320)
        let rect = NSRect(x: (bounds.width - 240 * scale)/2, y: (bounds.height - 320 * scale)/2,
                          width: 240 * scale, height: 320 * scale)
        if let image, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState(); context.interpolationQuality = filtered ? .low : .none
            context.clip(to: rect)
            context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1,y: -1)
            let zoom: CGFloat = controls.zoomHeld ? 2 : 1
            context.draw(image,in: NSRect(x:rect.width*(1-zoom)/2,y:rect.height*(1-zoom)/2,width:rect.width*zoom,height:rect.height*zoom)); context.restoreGState()
        }
        if paused || menuOpen || failure != nil {
            NSColor.black.withAlphaComponent(0.82).setFill(); bounds.fill()
            if let failure { text("Futari stopped", y: 100, size: 26); text(failure, y: 155, size: 14) }
            else if menuOpen {
                text("Mushihimesama Futari", y: 70, size: 25)
                for (index,item) in menuItems.enumerated() { text((index == menuIndex ? "› " : "  ")+item, y: 140+CGFloat(index)*36, size: 19) }
                text("Move: arrows / WASD   Confirm: J / Return", y: 430, size: 13)
                text("J shot   K / X auto   L bomb   \\ credit", y: 458, size: 13)
            } else { text("Paused", y: bounds.midY-20, size: 28) }
        }
    }
    private func text(_ string: String,y: CGFloat,size: CGFloat) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (string as NSString).draw(in: NSRect(x: 16,y: y,width: bounds.width-32,height: 70),
                                 withAttributes: [.font:NSFont.systemFont(ofSize:size),.foregroundColor:NSColor.white,.paragraphStyle:style])
    }
}

@main final class FutariApplication: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var view: FutariView!
    static func main() {
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
            window.title = "Mushihimesama Futari"; window.contentView = view; window.contentAspectRatio = NSSize(width:3,height:4)
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
