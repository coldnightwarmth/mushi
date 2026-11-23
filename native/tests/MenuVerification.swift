import AppKit

/// Uses only synthetic events delivered to an offscreen view. Never starts an
/// application run loop, creates a window, posts input, or opens an audio device.
func verifyFutariMenu(resources:URL,inputs:URL,folder:URL) throws {
    struct Failure:Error,CustomStringConvertible {let description:String}
    var checks=0
    func check(_ value:Bool,_ message:String)throws {checks+=1;if !value {throw Failure(description:message)}}
    _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let settings=folder.appendingPathComponent("menu-check.settings")
    try? FileManager.default.removeItem(at:settings)
    let view=FutariView(resources:resources,settings:settings,headless:true)
    guard let game=view.game else {throw Failure(description:view.failure ?? "Create game")}
    var events=[Int:(UInt8,UInt8)]()
    for line in try String(contentsOf:inputs,encoding:.utf8).split(separator:"\n") {
        let v=line.split(whereSeparator:{$0.isWhitespace}).compactMap{Int($0)}
        if v.count==3 {events[v[0]]=(UInt8(v[1]),UInt8(v[2]))}
    }
    var ports:(UInt8,UInt8)=(255,255)
    func step(_ d:UInt8=191)throws {try check(futari_frame(game,255,d)==1,String(cString:futari_error(game)))}
    for f in 0..<4000 {if let p=events[f]{ports=p};try check(futari_frame(game,ports.0,ports.1)==1,"native menu replay")}
    try check(futari_scene(game)==3,"Original gameplay reached")
    let historyBudget=futari_custom_status(game)
    try check(historyBudget.rewind_frames>=60 && historyBudget.rewind_bytes<=192*1024*1024,"bounded rewind allocations after extended recording")
    view.invincible=true;view.applyCustomOptions();view.refreshImage()
    func key(_ code:UInt16,up:Bool=false,repeated:Bool=false) {
        let event=NSEvent.keyEvent(with:up ? .keyUp:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:repeated,keyCode:code)!
        if up {view.keyUp(with:event)}else{view.keyDown(with:event)}
    }
    func snapshot(_ name:String)throws {
        let w=Int(view.bounds.width),h=Int(view.bounds.height)
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:w*4,bitsPerPixel:32)!
        let base=NSGraphicsContext(bitmapImageRep:bitmap)!,cg=base.cgContext
        NSGraphicsContext.saveGraphicsState();cg.translateBy(x:0,y:CGFloat(h));cg.scaleBy(x:1,y:-1)
        NSGraphicsContext.current=NSGraphicsContext(cgContext:cg,flipped:true);view.draw(view.bounds);NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name+".png"))
    }
    func pixels()->[UInt8] {var p=[UInt8](repeating:0,count:240*320*4);futari_pixels(game,&p);return p}
    key(38);key(48)
    try check(view.menuOpen && view.controls.nextFrame().rawValue==0,"Tab clears gameplay input")
    let before=futari_frame_number(game);view.advanceTime(1)
    try check(before==futari_frame_number(game),"modal menu stops simulation")
    key(48,repeated:true);try check(view.menuOpen,"repeat Tab ignored");key(53)
    try check(!view.menuOpen && !view.paused,"Escape closes modal menu")
    key(49);key(48);key(48);try check(view.paused,"prior pause restored");key(49)
    view.setMenu(true)
    try check(view.menuEntries.count==MetaAction.allCases.count,"every custom action represented")
    try check(!view.menuEntries.first{$0.action == .combined}!.enabled,"combined mode locked during run")
    view.setFrameSize(NSSize(width:860,height:760));view.refreshImage();try snapshot("menu-run")
    for action:MetaAction in [.infiniteCredits,.infiniteCharge,.exploration,.chargeZoom,.boost,.hud,.tallScreen,.sound] {
        let prior=view.menuEntries.first{$0.action==action}!.value
        view.activateMenu(action);try check(view.menuEntries.first{$0.action==action}!.value != prior,"toggle \(action)")
        view.activateMenu(action);try check(view.menuEntries.first{$0.action==action}!.value==prior,"restore \(action)")
    }
    for action:MetaAction in [.invincibility,.horizontal,.filtering,.artMaster,.artMemory] {
        let prior=view.menuEntries.first{$0.action==action}!.value
        view.activateMenu(action);view.activateMenu(action,direction:-1)
        try check(view.menuEntries.first{$0.action==action}!.value==prior,"bidirectional cycle \(action)")
    }
    // Input and audio timing use the same selected rate, including 10x.
    view.setMenu(false)
    let source=(0..<267).map{Float(sin(Double($0)/7))}
    for rate in [0.25,0.5,1.0,2,4,10] {
        view.customOptions.speed=rate;view.accumulator=0
        let frame=futari_frame_number(game)
        view.advanceTime(view.interval*0.5/rate);try check(futari_frame_number(game)==frame,"rate \(rate) premature frame")
        view.advanceTime(view.interval*0.6/rate);try check(futari_frame_number(game)==frame+1,"rate \(rate) frame timing")
        view.audioPhase=0;var output=[Float]()
        source.withUnsafeBufferPointer {p in for _ in 0..<10 {output+=view.resampleAudio(p.baseAddress!,count:p.count,rate:rate)}}
        try check(abs(Double(output.count)-2670/rate)<=1 && output.allSatisfy{$0.isFinite},"rate \(rate) audio duration")
    }
    view.customOptions.speed=1;key(14);try check(view.playbackRate==4,"E fast-forward");key(14,up:true);try check(view.playbackRate==1,"E release");
    key(12);try check(view.rewinding,"Q rewind");key(12,up:true);try check(!view.rewinding,"Q release");
    let protection=view.invincible;key(34);try check(view.customOptions.infiniteLives,"I protection shortcut");key(34);key(34);key(34);try check(view.invincible==protection,"I cycles protection");
    key(27);try check(view.customOptions.background == .red,"minus background");view.customOptions.background = .art
    key(24);try check(view.hideHUD,"plus hides HUD");key(24)
    view.setMenu(true)
    let native=pixels()
    // The four target groups form a disjoint partition of visible native actors.
    // Check the actual game, not only synthetic filter canvases.
    let groupCount=240*320
    var targets=[[UInt8]]()
    for kind in 6..<10 {
        var bytes=[UInt8](repeating:0,count:groupCount*4)
        futari_layer_pixels(game,0,Int32(kind),240,320,&bytes);targets.append(bytes)
    }
    for i in 0..<groupCount {
        try check(targets.filter{$0[i*4+3]>0}.count<=1,"overlapping native target ownership")
    }
    try check(targets[1].enumerated().contains{$0.offset%4==3 && $0.element>0},"missing live player group")
    try check(targets[2].enumerated().contains{$0.offset%4==3 && $0.element>0},"missing enemy group")
    view.customOptions.artScopes=ArtScopeSettings();view.customOptions.trailStyle = .off
    let plain=view.visuals.render(game,options:view.customOptions,hideHUD:false,rewinding:false,width:240,height:320)
    let nativeColors=stride(from:0,to:native.count,by:4).map{UInt32(native[$0])|UInt32(native[$0+1])<<8|UInt32(native[$0+2])<<16|0xff000000}
    try check(plain.pixels==nativeColors,"target groups do not reconstruct native pixels")
    var nativeHUD=[UInt8](repeating:0,count:groupCount*4);futari_layer_pixels(game,0,3,240,320,&nativeHUD)
    for scope:ArtOptions.Scope in [.background,.nonPlayer,.player,.enemies] {
        view.customOptions.artScopes=ArtScopeSettings();view.customOptions.artScopes.select(scope)
        view.customOptions.art[.foldedStage]=1;view.visuals.clear()
        let transformed=view.visuals.render(game,options:view.customOptions,hideHUD:false,rewinding:false,width:240,height:320)
        let protected=scope == .player ? [2,3]:scope == .enemies || scope == .nonPlayer ? [1]:[1,2,3]
        for group in protected {for i in 0..<groupCount where targets[group][i*4+3]>0 && nativeHUD[i*4+3]==0 {
            try check(transformed.pixels[i]==nativeColors[i],"\(scope) changed protected native group \(group)")
        }}
    }
    view.customOptions.artScopes=ArtScopeSettings();view.visuals.clear()
    for background in StageBackground.allCases {view.customOptions.background=background;view.refreshImage()}
    try check(native==pixels(),"background render does not alter native frame")
    view.customOptions.background = .art
    var variants=0
    for effect in ArtEffect.allCases {
        for variant in 1..<effect.choices.count {
            view.customOptions.artScopes=ArtScopeSettings();view.customOptions.art[effect]=variant;view.visuals.clear()
            for _ in 0..<12 {try step();view.refreshImage()}
            try check(view.image?.width==240 && view.image?.height==320,"render \(effect.title) \(variant)")
            variants+=1
        }
    }
    view.customOptions.artScopes=ArtScopeSettings();view.customOptions.art[.flowers]=1;view.customOptions.art[.foldedStage]=2
    view.menuIndex=MetaAction.allCases.firstIndex(of:.flowers)!;view.menuScroll=view.menuRowPositions[view.menuIndex]-240;view.refreshImage();try snapshot("menu-art")
    view.customOptions.artScopes=ArtScopeSettings();view.customOptions.artScopes.select(.background);view.customOptions.art[.rasterFabric]=1
    let actorsCount=240*320*4;var actors=[UInt8](repeating:0,count:actorsCount),hud=actors,effects=actors
    futari_layer_pixels(game,0,6,240,320,&effects);futari_layer_pixels(game,0,2,240,320,&actors);futari_layer_pixels(game,0,3,240,320,&hud)
    let bkg=view.visuals.render(game,options:view.customOptions,hideHUD:false,rewinding:false,width:240,height:320)
    for i in 0..<240*320 where actors[i*4+3]>0 && hud[i*4+3]==0 && effects[i*4+3]==0 {
        let c=UInt32(actors[i*4])|UInt32(actors[i*4+1])<<8|UInt32(actors[i*4+2])<<16|0xff000000
        try check(bkg.pixels[i]==c,"background scope changed an actor")
    }
    view.customOptions.artScopes=ArtScopeSettings()
    var timings=[String:Double]()
    for style in TrailStyle.allCases {
        view.customOptions.trailStyle=style;view.visuals.clear();view.applyCustomOptions()
        let start=ProcessInfo.processInfo.systemUptime
        for _ in 0..<130 {try step();view.refreshImage()}
        timings[style.rawValue]=(ProcessInfo.processInfo.systemUptime-start)*1000/130
        try check(view.image != nil,"trail \(style)")
    }
    view.customOptions.trailStyle = .fade;view.customOptions.art[.videoFeedback]=1;view.visuals.clear();view.applyCustomOptions()
    var saved=[UInt64:Data]()
    for _ in 0..<60 {try step();view.refreshImage();saved[futari_frame_number(game)]=view.image!.dataProvider!.data! as Data}
    view.activateMenu(.rewind);try check(view.rewinding && !view.menuOpen,"rewind starts from menu")
    try check(futari_rewind(game,30)==30,"native rewind history available");view.refreshImage()
    try check(view.image!.dataProvider!.data! as Data==saved[futari_frame_number(game)],"rewind restores custom display")
    key(12,up:true);try check(view.image!.dataProvider!.data! as Data==saved[futari_frame_number(game)],"rewind release preserves custom display")
    key(48);try check(view.menuOpen && !view.rewinding,"Tab stops rewind")
    view.visuals.clear();view.activateMenu(.resetArt);try check(!view.customOptions.art.active,"reset art")
    view.menuIndex=MetaAction.allCases.firstIndex(of:.speed)!;view.menuScroll=10000;view.clampMenuScroll();view.refreshImage();try snapshot("menu-time")
    let top=view.menuScroll;view.moveMenu(-1);try check(view.menuScroll<=top,"scroll selection visibility")
    view.setFrameSize(NSSize(width:320,height:360));view.menuIndex=0;view.menuScroll=0;try snapshot("menu-small")
    view.customOptions.trailStyle = .off;view.customOptions.horizontalMode = .open;view.setFrameSize(NSSize(width:600,height:900));view.refreshImage()
    try check(view.image?.width==304 && view.image?.height==384,"expanded native viewport")
    view.activateMenu(.restartStage);try check(!view.menuOpen && !view.paused && futari_status(game).stage==0,"restart stage")
    view.activateMenu(.title);for _ in 0..<180 {if futari_scene(game)==1 {break};try step(255)};try check(futari_scene(game)==1,"title return")
    view.setMenu(true);view.activateMenu(.combined);view.activateMenu(.combined)
    try check(view.customOptions.combinedOpening == .endless && view.customOptions.infiniteLives && !view.exploration,"endless adaptation")
    view.activateMenu(.credit);try check(!view.menuOpen && view.controls.nextFrame().contains(.credit),"menu credit pulse")
    try verifyFutariEffects(view:view,folder:folder)
    let report:[String:Any]=["checks":checks,"actions":MetaAction.allCases.count,"effect_variants":variants,"trail_styles":TrailStyle.allCases.count,"headless":true,"audio_device_opened":view.audioReady,"trail_frame_ms":timings,"rewind_frames_at_budget":historyBudget.rewind_frames,"rewind_bytes_at_budget":historyBudget.rewind_bytes]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("verification.json"))
    print("PASS \(checks) offscreen checks, \(MetaAction.allCases.count) menu actions, \(variants) effect variants, \(TrailStyle.allCases.count) trail styles; no window, audio device or posted input")
}
