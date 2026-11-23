import Foundation

/// Platform-independent menu vocabulary/preferences. A Windows frontend can
/// reuse these actions without importing the macOS window or input layer.
enum MetaAction: CaseIterable {
    case resume, restart, restartStage, title, credit, operatorSettings
    case infiniteCredits, infiniteCharge, combined, formation, exploration, chargeZoom, invincibility, boost
    case background, hud, tallScreen, horizontal, filtering, fullscreen
    case trails, artMaster, slitScan, timeBands, videoFeedback, datamosh, codecDatamosh, rasterFabric
    case pixelSediment, tileShuffle, scanlineWeaving, misregistration, inkBleed, negativeSpace
    case flowers, foldedStage, typography, artPresets, artMemory, randomArt, resetArt
    case pause, speed, rewind, sound
    var artEffect: ArtEffect? {
        switch self {
        case .slitScan:return .slitScan
        case .timeBands:return .timeBands
        case .videoFeedback:return .videoFeedback
        case .datamosh:return .datamosh
        case .codecDatamosh:return .codecDatamosh
        case .rasterFabric:return .rasterFabric
        case .pixelSediment:return .pixelSediment
        case .tileShuffle:return .tileShuffle
        case .scanlineWeaving:return .scanlineWeaving
        case .misregistration:return .misregistration
        case .inkBleed:return .inkBleed
        case .negativeSpace:return .negativeSpace
        case .flowers:return .flowers
        case .foldedStage:return .foldedStage
        case .typography:return .typography
        default:return nil
        }
    }
    var section: String {
        switch self {
        case .resume,.restart,.restartStage,.title,.credit,.operatorSettings:return "Run"
        case .infiniteCredits,.infiniteCharge,.combined,.formation,.exploration,.invincibility,.boost,.chargeZoom:return "Custom play"
        case .background,.hud,.filtering,.tallScreen,.horizontal,.fullscreen:return "Display"
        case .pause,.speed,.rewind,.sound:return "Time & sound"
        case .artMaster,.trails,.slitScan,.timeBands,.videoFeedback,.datamosh,.codecDatamosh,.rasterFabric,
             .pixelSediment,.tileShuffle,.scanlineWeaving,.misregistration,.inkBleed,.negativeSpace,
             .flowers,.foldedStage,.typography,.artPresets,.artMemory,.randomArt,.resetArt:return "Art effects"
        }
    }
    var title: String {
        switch self {
        case .resume:return "Close menu"
        case .pause:return "Pause game"
        case .restart:return "Restart run"
        case .restartStage:return "Restart stage"
        case .operatorSettings:return "Operator settings"
        case .title:return "Return to title"
        case .credit:return "Insert credit"
        case .infiniteCredits:return "Infinite credits"
        case .infiniteCharge:return "Infinite bombs"
        case .combined:return "Combined stages"
        case .formation:return "Reco/Palm formation"
        case .exploration:return "Free exploration"
        case .invincibility:return "Invincibility"
        case .boost:return "Quick boost"
        case .chargeZoom:return "Camera zoom-in"
        case .trails:return "Image trails"
        case .background:return "Stage background"
        case .hud:return "HUD"
        case .filtering:return "Pixel filtering"
        case .tallScreen:return "Expanded vertical"
        case .fullscreen:return "Fullscreen"
        case .horizontal:return "Expanded horizontal"
        case .speed:return "Playback speed"
        case .rewind:return "Rewind 2×"
        case .sound:return "Sound"
        case .artMaster:return "Other effects"
        case .artPresets:return "Presets"
        case .artMemory:return "Effect memory"
        case .randomArt:return "Randomize effects"
        case .resetArt:return "Reset effects"
        case .slitScan,.timeBands,.videoFeedback,.datamosh,.codecDatamosh,.rasterFabric,
             .pixelSediment,.tileShuffle,.scanlineWeaving,.misregistration,.inkBleed,.negativeSpace,
             .flowers,.foldedStage,.typography:return artEffect!.title
        }
    }
}
struct CustomGameOptions {
    enum CombinedOpening: Int,CaseIterable {
        case off,on,endless
        var title: String { ["Off","On","Endless"][rawValue] }
    }
    var artScopes=ArtScopeSettings()
    var art: ArtOptions { get { artScopes.current } set { artScopes.current=newValue } }
    var infiniteCredits=false
    var infiniteLives=false
    var absorbBullets=false
    var infiniteCharge=false
    var explorationBoost=true
    var chargeCameraZoom=true
    var expandTallScreens=true
    var combinedOpening=CombinedOpening.off
    var combinedStart: Bool {
        get { combinedOpening != .off }
        set { if !newValue { combinedOpening = .off } else if combinedOpening == .off { combinedOpening = .on } }
    }
    var formationStart=false
    enum Horizontal: Int,CaseIterable { case off,on,open
        var title: String { ["Off","On","Open"][rawValue] }
    }
    var horizontalMode=Horizontal.off
    var horizontal: Bool {
        get { horizontalMode != .off }
        set { horizontalMode = newValue ? .on:.off }
    }
    var speed=1.0
    // Compatibility for older offscreen checks; live UI cycles all rates.
    var fastPlayback: Bool { get { speed>1 } set { speed=newValue ? 4:1 } }
    var trailStyle=TrailStyle.off
    var background=StageBackground.art
}
struct MetaMenuEntry {
    let action: MetaAction
    let value: String
    var enabled=true
    var help=""
}


enum TrailStyle: String, CaseIterable {
    case off="Off", normal="Normal", spaced="Spaced", sparse="Sparse", fade="Fade", loop="Loop", scale="Scale", scale2x="Scale2x", flash="Flash", random="Random"
    var menuHelp: String {
        switch self {
        case .off:return "No afterimages. Cycle this option to add trails to players, bullets, pickups and effects."
        case .normal:return "Leave solid afterimages behind players, bullets, pickups and effects as they move."
        case .spaced:return "Leave solid afterimages half as often as Normal, for wider gaps between echoes."
        case .sparse:return "Leave widely separated afterimages, captured once every 24 frames."
        case .fade:return "Leave afterimages that gradually fade away."
        case .loop:return "Leave afterimages that repeatedly disappear and reappear, making trails look like they are drawn over and over."
        case .scale:return "Leave afterimages that grow larger over time."
        case .scale2x:return "Leave afterimages that grow twice as fast as Scale."
        case .flash:return "Leave afterimages that blink on and off. Each echo keeps its own randomly chosen rhythm."
        case .random:return "Use random observed sprite variants for afterimages, matched by their native draw family. Gameplay animation and hitboxes stay intact."
        }
    }
    var captureInterval: UInt32 { self == .sparse ? 24:(self == .spaced ? 2:1) }
    var scaleRate: Double { self == .scale2x ? 12:(self == .scale ? 6:0) }
    var keepsStampMetadata: Bool { scaleRate>0 || self == .flash }
    func next(_ direction: Int=1) -> Self {
        let all=Self.allCases;return all[(all.firstIndex(of:self)!+direction+all.count)%all.count]
    }
}
enum StageBackground: String, CaseIterable {
    case art="Art", red="Red", orange="Orange", yellow="Yellow", green="Green", cyan="Cyan", blue="Blue", indigo="Indigo", violet="Violet", black="Black", white="White"
    var rgba: UInt32 {
        let rgb: UInt32
        switch self {
        case .art,.black:rgb=0x000000
        case .red:rgb=0xed2024
        case .orange:rgb=0xff8000
        case .yellow:rgb=0xffff00
        case .green:rgb=0x00ff40
        case .cyan:rgb=0x00ffff
        case .blue:rgb=0x0080ff
        case .indigo:rgb=0x6000ff
        case .violet:rgb=0xd000ff
        case .white:rgb=0xffffff
        }
        return 0xff000000|((rgb&255)<<16)|(rgb&0xff00)|(rgb>>16)
    }
    func next(_ direction: Int=1) -> Self {
        let all=Self.allCases;return all[(all.firstIndex(of:self)!+direction+all.count)%all.count]
    }
}
