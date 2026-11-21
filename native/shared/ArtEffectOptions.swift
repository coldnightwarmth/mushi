import Foundation

enum ArtEffect: Int, CaseIterable {
    case slitScan, timeBands, videoFeedback, datamosh, rasterFabric
    case pixelSediment, tileShuffle, scanlineWeaving, misregistration, inkBleed
    case negativeSpace, flowers, foldedStage, typography
    var title: String {
        ["Slit-scan","Time bands","Video feedback","Motion-block datamosh",
         "Raster fabric","Pixel sediment","Tile shuffle","Scanline weaving","Misregistration",
         "Ink bleed","Negative space","Explosions as flowers","Folded stage",
         "Typography invasion"][rawValue]
    }
    var choices: [String] {
        let pairs=[["Vertical","Horizontal","Fast V","Fast H","Thin V","Thin H"],["Drift","Alternate"],["Zoom","Spiral"],
                   ["Loose","Heavy","Streak","Scatter"],["Ripple","Shred"],["Light","Heavy","Burst"],["Small","Large","Burst"],
                   ["Fine","Coarse"],["Split","Orbit"],["Soft","Flood"],["Past","Color"],
                   ["Garden","Dense"],["Mirror","Kaleido","Vertical","Horizontal","Pinwheel","Tunnel"],["Drift","Storm","Rain","Orbit","Ticker"]]
        return ["Off"]+pairs[rawValue]
    }
    var help: String {
        ["Stretch recent motion into ribbons. Fast sweeps through time faster; Thin uses finer, faster ribbons.",
         "Give horizontal bands different delays. Alternate sends neighboring bands backward through recent images.",
         "Blend recent images into the scene with a gentle zoom or rotating spiral.",
         "Carry old images in moving blocks. Heavy retains more; Streak stretches motion and Scatter scatters small blocks.",
         "Ripple or shred the scene into independently displaced pixel rows.",
         "Enemies explode into colorful pixels. Light and Heavy settle into drifting piles; Burst scatters without accumulating.",
         "Shuffle small or large tiles. Burst sends a temporary ring of shuffled tiles outward from each destroyed enemy.",
         "Blend fine or coarse scanlines from the combined stages, or delayed images in a single stage.",
         "Separate the red, green and blue channels. Orbit continuously moves the separated colors.",
         "Spread bright sprite colors outward like wet ink. Flood spreads farther.",
         "Turn sprite silhouettes into windows onto older images or shifting color.",
         "Explosion sprites become flowers that grow and slowly turn, then fade.",
         "Reflect the stage, turn it into a kaleidoscope or pinwheel, or fold it through a moving tunnel.",
         "Fill the scene with original menu lettering, credit prompts, life icons and meters. Drift, storm, rain, orbit or scroll them across."][rawValue]
    }
}

struct ArtOptions: Equatable {
    enum Scope: Int, CaseIterable {
        case off,on,background
        var title: String { ["Off","On","Bkg"][rawValue] }
    }
    var scope=Scope.on
    var enabled: Bool {
        get { scope != .off }
        set { if !newValue { scope = .off } else if scope == .off { scope = .on } }
    }
    var backgroundOnly: Bool { scope == .background }
    mutating func cycleScope(_ direction: Int) { scope=Scope(rawValue:(scope.rawValue+direction+3)%3)! }
    var values=[Int](repeating:0,count:ArtEffect.allCases.count)
    var memoryIndex=1
    var memoryTicks: Int { [58,116,232][memoryIndex] }
    var active: Bool { enabled && values.contains(where:{$0 != 0}) }
    subscript(_ effect: ArtEffect) -> Int {
        get { enabled ? values[effect.rawValue]:0 }
        set { values[effect.rawValue]=newValue }
    }
    mutating func cycle(_ effect: ArtEffect,_ direction: Int) {
        let i=effect.rawValue;let count=effect.choices.count;values[i]=(values[i]+direction+count)%count
    }
    var needsSprites: Bool {
        (self[.pixelSediment]>0 && self[.pixelSediment]<3) ||
            [.slitScan,.timeBands,.videoFeedback,.datamosh,.scanlineWeaving,.typography,.inkBleed,.negativeSpace,.flowers].contains{self[$0]>0}
    }
}
