import AppKit

extension FutariView {
    func applyCustomOptions() {
        guard let game else{return}
        var options=FutariCustomOptions()
        options.infinite_credits=customOptions.infiniteCredits ? 1:0
        options.infinite_bombs=customOptions.infiniteCharge ? 1:0
        options.protection=customOptions.absorbBullets ? 3:(customOptions.infiniteLives ? 2:(invincible ? 1:0))
        options.formation=customOptions.formationStart ? 1:0
        options.combined=Int32(customOptions.combinedOpening.rawValue)
        options.exploration=exploration ? 1:0
        options.boost=customOptions.explorationBoost ? 1:0
        options.horizontal=Int32(customOptions.horizontalMode.rawValue)
        options.rewind_enabled=1
        options.random_trails=customOptions.trailStyle == .random ? 1:0
        futari_configure(game,options)
    }
    var menuEntries:[MetaMenuEntry] {
        let status=game.map{futari_status($0)},custom=game.map{futari_custom_status($0)}
        let playing=status?.phase==3
        func on(_ b:Bool)->String {b ? "On":"Off"}
        return MetaAction.allCases.map {a in
            switch a {
            case .resume:return .init(action:a,value:"Tab",help:"Close this menu and return to the game.")
            case .restart:return .init(action:a,value:"R",help:"Restart this run from its first stage with the selected character and shot type.")
            case .restartStage:return .init(action:a,value:status.map{"\($0.stage+1)/5"} ?? "-",enabled:status?.can_restart_stage != 0,help:"Restore this stage's opening, including enemies, resources and sound.")
            case .title:return .init(action:a,value:"Esc",help:"Return to the original title and selection menus.")
            case .credit:return .init(action:a,value:"\\",help:"Insert one credit and close the menu.")
            case .operatorSettings:return .init(action:a,value:"Open",help:"Open the original operator settings. Use Save & Exit to keep cabinet changes.")
            case .infiniteCredits:return .init(action:a,value:on(customOptions.infiniteCredits),help:"Keep nine credits available for starts and continues.")
            case .infiniteCharge:return .init(action:a,value:on(customOptions.infiniteCharge),help:"Keep three bombs available for Reco and Palm. This is Futari's equivalent of infinite special charge.")
            case .combined:return .init(action:a,value:customOptions.combinedOpening.title,enabled:[0,1,2].contains(status?.phase ?? 0),help:"Start stages 1, 2 and 3 together on the next run. Endless loops their openings independently. Each world keeps its own enemies and collisions.")
            case .formation:return .init(action:a,value:on(customOptions.formationStart),enabled:custom?.wing_active != 1,help:"Control Reco and Palm together through the original two-player game. Once joined, the partner stays until you return to title.")
            case .exploration:return .init(action:a,value:on(exploration),enabled:customOptions.combinedOpening != .endless,help:"Move forward or backward through stage scenery. Forward movement advances stage events; enemies remain active.")
            case .chargeZoom:return .init(action:a,value:on(customOptions.chargeCameraZoom),help:"Hold Z to zoom the camera in. Release it to return to the current view.")
            case .invincibility:return .init(action:a,value:customOptions.absorbBullets ? "Absorb":customOptions.infiniteLives ? "Infinite lives":on(invincible),help:"Cycle normal damage, protection, infinite respawns and absorbing bullets to replenish bombs.")
            case .boost:return .init(action:a,value:on(customOptions.explorationBoost),help:"Hold Shift to move 2.5 times faster. Works with either character and shot type.")
            case .trails:return .init(action:a,value:customOptions.trailStyle.rawValue,help:customOptions.trailStyle.menuHelp)
            case .background:return .init(action:a,value:customOptions.background.rawValue,help:"Show original scenery or replace it with a solid color. Actors and HUD remain visible.")
            case .hud:return .init(action:a,value:on(!hideHUD),help:"Show or hide score, lives, bombs, credits and boss meters.")
            case .tallScreen:return .init(action:a,value:on(customOptions.expandTallScreens),help:"Reveal the native vertical overscan in tall windows, up to 384 pixels high.")
            case .horizontal:return .init(action:a,value:customOptions.horizontalMode.title,help:"Reveal side areas up to 304 pixels wide. Open also extends the player's movement bounds.")
            case .filtering:return .init(action:a,value:smoothFilteringOverride.map{$0 ? "Smooth":"Sharp"} ?? "Auto",help:"Cycle automatic, sharp or smooth pixel filtering.")
            case .fullscreen:return .init(action:a,value:on(window?.styleMask.contains(.fullScreen)==true),enabled:window != nil,help:"Toggle fullscreen. Control-Command-F also works.")
            case .pause:return .init(action:a,value:on(menuOpen ? menuWasPaused:paused),help:"Keep the game paused after closing the menu.")
            case .speed:return .init(action:a,value:String(format:"%gx",customOptions.speed),help:"Set gameplay and audio speed: 0.25, 0.5, 1, 2, 4 or 10 times normal.")
            case .rewind:return .init(action:a,value:"Start",enabled:playing && (custom?.rewind_frames ?? 0)>0,help:"Rewind recent gameplay at 2x speed. Tab stops; close the menu to continue from that point.")
            case .sound:return .init(action:a,value:on(!muted),help:"Toggle all music and sound effects.")
            case .artMaster:return .init(action:a,value:customOptions.art.scope.title,help:"On affects the scene; Bkg keeps actors clear. HUD and menu stay outside the effects. Off keeps your selections.")
            case .artMemory:return .init(action:a,value:["1 sec","2 sec","4 sec"][customOptions.art.memoryIndex],help:"Choose how far time-based effects reach into recent images.")
            case .clearArt:return .init(action:a,value:"Clear",help:"Clear trails, flowers and accumulated images without changing options or restarting.")
            case .resetArt:return .init(action:a,value:"All off",help:"Turn off all art effects and clear their canvas. Image trails keep their setting.")
            default:
                let e=a.artEffect!
                let help=e == .pixelSediment ? "Native explosions and impacts shed colorful pixels. Light and Heavy settle into drifting piles; Burst scatters without accumulating.":e == .tileShuffle ? "Shuffle small or large tiles. Burst sends rings out from native explosions and impacts.":e.help
                return .init(action:a,value:e.choices[customOptions.art.values[e.rawValue]],help:help)
            }
        }
    }
    func activateMenu(direction:Int) {activateMenu(menuEntries[menuIndex].action,direction:direction)}
    func activateMenu(_ action:MetaAction,direction:Int=1) {
        guard menuEntries.first(where:{$0.action==action})?.enabled==true else{return}
        switch action {
        case .resume:setMenu(false)
        case .restart:menuWasPaused=false;setMenu(false);customOptions.speed=1;restoreRun(title:false)
        case .restartStage:menuWasPaused=false;setMenu(false);restoreRun(title:false,stage:true)
        case .title:menuWasPaused=false;setMenu(false);customOptions.speed=1;restoreRun(title:true)
        case .credit:
            menuWasPaused=false;setMenu(false);_ = controls.keyDown(42);controls.keyUp(42)
        case .operatorSettings:
            if let game {futari_test_switch(game,1);testSwitchFrames=180};menuWasPaused=false;setMenu(false)
        case .infiniteCredits:customOptions.infiniteCredits.toggle()
        case .infiniteCharge:customOptions.infiniteCharge.toggle()
        case .combined:
            customOptions.combinedOpening = .init(rawValue:(customOptions.combinedOpening.rawValue+direction+3)%3)!
            if customOptions.combinedOpening == .endless {exploration=false;customOptions.infiniteLives=true;customOptions.absorbBullets=false;invincible=false}
        case .formation:customOptions.formationStart.toggle()
        case .exploration:exploration.toggle();visuals.clear()
        case .invincibility:
            let value=customOptions.absorbBullets ? 3:(customOptions.infiniteLives ? 2:(invincible ? 1:0)),next=(value+direction+4)%4
            invincible=next==1;customOptions.infiniteLives=next==2;customOptions.absorbBullets=next==3
        case .boost:customOptions.explorationBoost.toggle()
        case .chargeZoom:customOptions.chargeCameraZoom.toggle()
        case .trails:customOptions.trailStyle=customOptions.trailStyle.next(direction);visuals.clear()
        case .background:customOptions.background=customOptions.background.next(direction)
        case .hud:hideHUD.toggle()
        case .tallScreen:customOptions.expandTallScreens.toggle()
        case .horizontal:customOptions.horizontalMode = .init(rawValue:(customOptions.horizontalMode.rawValue+direction+3)%3)!
        case .filtering:
            let choices:[Bool?]=[nil,false,true],i=choices.firstIndex(of:smoothFilteringOverride) ?? 0
            smoothFilteringOverride=choices[(i+direction+3)%3];filtered=smoothFilteringOverride ?? false
        case .fullscreen:window?.toggleFullScreen(nil)
        case .pause:if menuOpen {menuWasPaused.toggle()}else{paused.toggle();syncAudio()}
        case .speed:
            let rates=[0.25,0.5,1,2,4,10],i=rates.firstIndex(of:customOptions.speed) ?? 2
            customOptions.speed=rates[(i+direction+rates.count)%rates.count];syncAudio();accumulator=0
        case .rewind:menuWasPaused=false;setMenu(false);paused=false;rewinding=true;syncAudio()
        case .sound:muted.toggle();player.volume=muted ? 0:1
        case .artMaster:customOptions.art.cycleScope(direction)
        case .artMemory:customOptions.art.memoryIndex=(customOptions.art.memoryIndex+direction+3)%3
        case .clearArt:visuals.clear()
        case .resetArt:customOptions.art=ArtOptions();visuals.clear()
        default:customOptions.art.cycle(action.artEffect!,direction)
        }
        applyCustomOptions();refreshImage();needsDisplay=true
    }
    var menuPanel:NSRect {NSRect(x:0,y:0,width:min(344,bounds.width),height:bounds.height)}
    var gamePresentationBounds:NSRect {
        guard menuOpen,bounds.width-menuPanel.width>=240 else{return bounds}
        return NSRect(x:menuPanel.width,y:0,width:bounds.width-menuPanel.width,height:bounds.height)
    }
    var menuListBottom:CGFloat {max(100,bounds.height-90)}
    var menuRowPositions:[CGFloat] {
        var y:CGFloat=42,section=""
        return menuEntries.map{e in if e.action.section != section {section=e.action.section;y+=20};let top=y;y+=28;return top}
    }
    func clampMenuScroll(){menuScroll=max(0,min(menuScroll,max(0,(menuRowPositions.last ?? 0)+28-menuListBottom)))}
    func moveMenu(_ direction:Int) {
        let entries=menuEntries
        for _ in entries.indices {menuIndex=(menuIndex+direction+entries.count)%entries.count;if entries[menuIndex].enabled {break}}
        let y=menuRowPositions[menuIndex]
        if y-menuScroll<42 {menuScroll=y-42}
        if y+28-menuScroll>menuListBottom {menuScroll=y+28-menuListBottom}
        clampMenuScroll();needsDisplay=true
    }
    func drawCustomMenu() {
        clampMenuScroll();let panel=menuPanel,entries=menuEntries,positions=menuRowPositions
        NSColor(calibratedWhite:0.035,alpha:0.98).setFill();panel.fill()
        RetroMenuFont.draw("Futari - Custom",in:NSRect(x:16,y:16,width:panel.width-32,height:22),scale:1.5,color:.white)
        NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:NSRect(x:0,y:42,width:panel.width,height:menuListBottom-42)).addClip()
        for (i,e) in entries.enumerated() {
            let y=positions[i]-menuScroll
            if i==0 || e.action.section != entries[i-1].action.section {RetroMenuFont.draw(e.action.section,in:NSRect(x:16,y:y-17,width:panel.width-32,height:14),scale:1,color:.gray)}
            if i==menuIndex {NSColor(calibratedWhite:0.16,alpha:1).setFill();NSRect(x:8,y:y,width:panel.width-16,height:26).fill()}
            let valueWidth:CGFloat=e.action == .invincibility ? 126:96
            RetroMenuFont.draw(e.action.title,in:NSRect(x:16,y:y+5,width:panel.width-valueWidth-34,height:20),scale:1.5,color:e.enabled ? .white:.gray)
            RetroMenuFont.draw(e.value,in:NSRect(x:panel.width-valueWidth-16,y:y+5,width:valueWidth,height:20),scale:1.5,color:e.enabled ? .lightGray:.gray,right:true)
        }
        NSGraphicsContext.restoreGraphicsState()
        RetroMenuFont.draw(entries[menuIndex].help,in:NSRect(x:16,y:menuListBottom+8,width:panel.width-32,height:70),scale:1,color:.lightGray,wrapWords:true)
    }
}
