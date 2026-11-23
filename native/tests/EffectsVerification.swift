import AppKit

/// Uses a private fixture library and an offscreen view. Never reads or writes
/// the user's presets, opens a game window, or starts an audio device.
func verifyFutariEffects(view:FutariView,folder: URL) throws {
    _=NSApplication.shared
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let fixtures=folder.appendingPathComponent(UUID().uuidString)
    func throwError(_ message:String) -> Never {fputs("FAIL effects: "+message+"\n",stderr);exit(1)}
    func check(_ ok: @autoclosure ()->Bool,_ message: String) { if !ok() { throwError(message) } }
    var first=EffectSettings();first.art.scope = .nonPlayer;first.art.memoryIndex=2;first.trails = .scale2x
    for effect in ArtEffect.allCases { first.art[effect]=effect.choices.count-1 }
    var second=first;second.art.scope = .off;second.trails = .random
    let url=fixtures.appendingPathComponent("roundtrip.plist"),library=EffectPresetLibrary(url:url)
    check(library.presets.isEmpty && library.loadError==nil,"new library was not empty")
    let firstSaved=try library.add(first),secondSaved=try library.add(second)
    check(firstSaved.number==1,"first preset wasn't 1")
    check(secondSaved.number==2,"second preset wasn't 2")
    let reopened=EffectPresetLibrary(url:url)
    check(reopened.presets.map{$0.settings}==[first,second],"relaunch lost settings, hidden Off choices, or order")
    let other=EffectPresetLibrary(url:url)
    _=try reopened.add(EffectSettings());_=try other.add(first)
    check(EffectPresetLibrary(url:url).presets.map{$0.number}==[1,2,3,4],"a stale instance replaced completed saves")
    let broken=fixtures.appendingPathComponent("invalid.plist"),original=Data("not a preset library".utf8)
    try original.write(to:broken)
    let invalid=EffectPresetLibrary(url:broken);check(invalid.loadError != nil,"invalid library was silently accepted")
    do { _=try invalid.add(first);throwError("overwrote invalid preset library") } catch { }
    let untouched=try Data(contentsOf:broken)
    check(untouched==original,"bad library was changed")
    struct Seeded: RandomNumberGenerator {
        var state:UInt64=0x8d1727c0de
        mutating func next()->UInt64 { state ^= state<<13;state ^= state>>7;state ^= state<<17;return state }
    }
    var random=Seeded(),scopes=Set<Int>(),trails=Set<String>(),memories=Set<Int>()
    var choices=Array(repeating:Set<Int>(),count:ArtEffect.allCases.count)
    for _ in 0..<512 {
        let settings=EffectSettings.randomized(using:&random)
        scopes.insert(settings.art.scope.rawValue);trails.insert(settings.trails.rawValue);memories.insert(settings.art.memoryIndex)
        for effect in ArtEffect.allCases {
            let value=settings.art.values[effect.rawValue]
            check(effect.choices.indices.contains(value),"randomized invalid \(effect.title)")
            choices[effect.rawValue].insert(value)
        }
    }
    check(scopes.count==ArtOptions.Scope.allCases.count && trails.count==TrailStyle.allCases.count && memories.count==3,"randomization omitted scope, trails or memory")
    for effect in ArtEffect.allCases { check(choices[effect.rawValue].count==effect.choices.count,"randomization omitted a \(effect.title) choice") }
    print("PASS preset persistence, sequential numbering, all settings including disabled modes, safe append/error handling, every randomized option.");fflush(stdout)

    verifyCodecDatamosh()
    var banks=ArtScopeSettings(),all=ArtOptions(),player=ArtOptions(),enemy=ArtOptions()
    all[.videoFeedback]=1;player[.rasterFabric]=2;enemy[.videoFeedback]=2
    banks.set(all,for:.on);banks.set(player,for:.player);banks.set(enemy,for:.enemies)
    check(banks.resolved(for:.player)[.videoFeedback]==1 && banks.resolved(for:.player)[.rasterFabric]==2,"scope inheritance")
    check(banks.resolved(for:.enemies)[.videoFeedback]==2,"specific enabled override")
    let plans=banks.plans
    for scope in ArtScopeSettings.editingScopes {banks.select(scope);check(banks.plans.map{$0.options}==plans.map{$0.options},"browsing changed running effects")}
    for group in ArtGroup.allCases {check(plans.filter{$0.groups.contains(group.mask)}.count==1,"duplicate effect pass")}
    banks.select(.off);check(!banks.active,"global Off");banks.select(.on)
    check(banks.resolved(for:.player)[.rasterFabric]==2,"Off erased settings")
    view.applyEffectSettings(EffectSettings(),as:.standard);view.setMenu(true)
    let initialFrame=view.game.map{futari_frame_number($0)}
    view.customOptions.art[.rasterFabric]=1
    let look=view.effectSettings
    check(view.menuEntries.first{$0.action == .artPresets}!.value=="Add","edits select Add")
    view.activateEffectPreset()
    check(view.effectPresets.presets.last?.settings==look,"menu saves a preset")
    view.applyEffectSettings(EffectSettings(),as:.standard)
    view.cycleEffectPreset(1);view.cycleEffectPreset(1)
    check(view.effectSettings==EffectSettings(),"browsing applied preset")
    view.activateEffectPreset();check(view.effectSettings==look,"menu loads selected preset")
    let saved=view.effectPresets.presets.count
    view.activateMenu(.randomArt)
    check(view.menuEntries.first{$0.action == .artPresets}!.value=="Add","randomize not savable")
    view.activateMenu(.resetArt)
    check(view.effectSettings==EffectSettings() && view.effectPresets.presets.count==saved,"reset erased saved presets")
    check(view.game.map{futari_frame_number($0)}==initialFrame && view.controls.nextFrame().rawValue==0,"effects menu advanced game or leaked input")
    // Every shared filter must preserve transparency on isolated actor layers.
    for effect in ArtEffect.allCases {
        var options=ArtOptions();options[effect]=effect.choices.count-1
        let engine=ArtEffectEngine()
        for tick in 0..<12 {
            var input=ArtBitmap(width:120,height:160)
            for y in 60..<76 {for x in (35+tick)..<(51+tick) {input.pixels[y*120+x]=0xff40c0ff}}
            var frame=ArtFrame(image:input);frame.transparent=true;frame.sprites=input;frame.effects=input
            let output=engine.render(frame,options:options,tick:tick,context:"alpha")
            check(output.pixels.contains{$0>>24==0},"opaque group canvas: \(effect.title)")
        }
    }
    print("PASS independent scope banks, isolated alpha, presets menu and unchanged simulation")
}
