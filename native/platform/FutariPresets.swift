import AppKit

extension FutariView {
    var effectSettings: EffectSettings {
        EffectSettings(scopes:customOptions.artScopes,trails:customOptions.trailStyle)
    }
    func synchronizePresetPicker() { effectPresetPicker.observe(effectSettings) }
    func cycleEffectPreset(_ direction: Int) {
        synchronizePresetPicker();effectPresetPicker.cycle(direction,presets:effectPresets.presets)
        presetSaveError=nil;needsDisplay=true
    }
    var effectPresetHelp: String {
        if let error=presetSaveError ?? effectPresets.loadError { return error }
        switch effectPresetPicker.selection {
        case .standard:return "Load the default effects. A/D or arrows browse; J, Enter or a click applies."
        case .add:return "Save these effects as a numbered preset. Press J, Enter or click to save. A/D or arrows browse."
        case .saved(let n):return "Load preset \(n). A/D or arrows browse; J, Enter or a click loads the selected preset."
        }
    }
    func applyEffectSettings(_ settings: EffectSettings,as choice: EffectPresetPicker.Choice) {
        customOptions.artScopes=settings.scopes;customOptions.trailStyle=settings.trails
        visuals.clear()
        effectPresetPicker.applied(settings,as:choice);presetSaveError=nil
        applyCustomOptions();refreshImage()
    }
    func activateEffectPreset() {
        synchronizePresetPicker()
        switch effectPresetPicker.selection {
        case .standard:applyEffectSettings(EffectSettings(),as:.standard)
        case .add:
            do {
                let saved=try effectPresets.add(effectSettings)
                effectPresetPicker.applied(effectSettings,as:.saved(saved.number));presetSaveError=nil
            } catch { presetSaveError="Could not save preset. "+error.localizedDescription }
        case .saved(let number):
            if let saved=effectPresets.presets.first(where:{$0.number==number}) { applyEffectSettings(saved.settings,as:.saved(number)) }
        }
        needsDisplay=true
    }
    /// The same rects are used for drawing and mouse hit-testing.
    func presetArrowRects(rowY: CGFloat)->(left:NSRect,right:NSRect) {
        (NSRect(x:menuPanel.width-140,y:rowY,width:24,height:26),
         NSRect(x:menuPanel.width-34,y:rowY,width:24,height:26))
    }
}
