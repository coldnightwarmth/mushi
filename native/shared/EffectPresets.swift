import Foundation

/// Only the Art effects section: loading a look never changes game rules,
/// movement, time, audio, window settings or the current run.
struct EffectSettings: Equatable {
    var scopes=ArtScopeSettings()
    var art: ArtOptions { get { scopes.current } set { scopes.current=newValue } }
    var trails=TrailStyle.off
    init(scopes: ArtScopeSettings=ArtScopeSettings(),trails: TrailStyle = .off) { self.scopes=scopes;self.trails=trails }
    init(art: ArtOptions,trails: TrailStyle = .off) { self.init(trails:trails);self.art=art }
    static func randomized<R: RandomNumberGenerator>(using random: inout R)->EffectSettings {
        var result=EffectSettings()
        result.trails=TrailStyle.allCases.randomElement(using:&random)!
        for scope in ArtScopeSettings.editingScopes {
            var options=ArtOptions();options.scope=scope;options.memoryIndex=Int.random(in:0..<3,using:&random)
            for effect in ArtEffect.allCases { options[effect]=Int.random(in:0..<effect.choices.count,using:&random) }
            result.scopes.set(options,for:scope)
        }
        result.scopes.select(ArtOptions.Scope.allCases.randomElement(using:&random)!)
        return result
    }
}

struct SavedEffectPreset: Codable {
    private struct ScopeSettings: Codable { let memorySeconds: Int,effects: [String:String] }
    let number: Int
    private let scope: String,memorySeconds: Int,trails: String,effects: [String:String]
    private let scopes: [String:ScopeSettings]?
    private let editingScope: String?
    init(number: Int,settings: EffectSettings) {
        self.number=number;scope=String(describing:settings.art.scope)
        editingScope=String(describing:settings.scopes.editingScope)
        memorySeconds=[1,2,4][settings.art.memoryIndex];trails=settings.trails.rawValue
        effects=Dictionary(uniqueKeysWithValues:ArtEffect.allCases.map {
            (String(describing:$0),$0.choices[settings.art.values[$0.rawValue]])
        })
        scopes=Dictionary(uniqueKeysWithValues:ArtScopeSettings.editingScopes.map { scope in
            let options=settings.scopes.configuration(for:scope)
            return (String(describing:scope),ScopeSettings(memorySeconds:[1,2,4][options.memoryIndex],effects:Dictionary(uniqueKeysWithValues:ArtEffect.allCases.map {
                (String(describing:$0),$0.choices[options.values[$0.rawValue]])
            })))
        })
    }
    var settings: EffectSettings {
        var result=EffectSettings()
        // Names rather than enum indexes keep saved presets stable when new
        // effects/options are inserted. Unknown future options default off.
        result.art.scope=ArtOptions.Scope.allCases.first{String(describing:$0)==scope} ?? .on
        result.art.memoryIndex=[1,2,4].firstIndex(of:memorySeconds) ?? 1
        result.trails=TrailStyle(rawValue:trails) ?? .off
        for effect in ArtEffect.allCases {
            result.art[effect]=effect.choices.firstIndex(of:effects[String(describing:effect)] ?? "Off") ?? 0
        }
        if let scopes=scopes {
            result.scopes=ArtScopeSettings()
            for scope in ArtScopeSettings.editingScopes {
                guard let saved=scopes[String(describing:scope)] else { continue }
                var options=ArtOptions();options.scope=scope;options.memoryIndex=[1,2,4].firstIndex(of:saved.memorySeconds) ?? 1
                for effect in ArtEffect.allCases { options[effect]=effect.choices.firstIndex(of:saved.effects[String(describing:effect)] ?? "Off") ?? 0 }
                result.scopes.set(options,for:scope)
            }
            result.scopes.select(ArtScopeSettings.editingScopes.first{String(describing:$0)==editingScope} ?? .on)
            result.scopes.select(ArtOptions.Scope.allCases.first{String(describing:$0)==scope} ?? .on)
        }
        return result
    }
}

final class EffectPresetLibrary {
    private struct Archive: Codable { var version=1;let presets: [SavedEffectPreset] }
    private enum ArchiveError: LocalizedError {
        case invalid
        var errorDescription: String? { "Saved effect presets could not be read. The existing file was left unchanged." }
    }
    let url: URL?
    private(set) var presets=[SavedEffectPreset]()
    private(set) var loadError: String?
    init(url: URL?=nil) {
        self.url=url
        if let url=url {
            do { presets=try Self.read(url) } catch { loadError=error.localizedDescription }
        }
    }
    private static func read(_ url: URL) throws -> [SavedEffectPreset] {
        let data: Data
        do { data=try Data(contentsOf:url) }
        catch let error as NSError where error.domain==NSCocoaErrorDomain && error.code==NSFileReadNoSuchFileError { return [] }
        let archive: Archive
        do { archive=try PropertyListDecoder().decode(Archive.self,from:data) }
        catch { throw ArchiveError.invalid }
        guard archive.version==1,archive.presets.allSatisfy({$0.number>0 && $0.number<Int.max}),
              Set(archive.presets.map{$0.number}).count==archive.presets.count else { throw ArchiveError.invalid }
        return archive.presets.sorted{$0.number<$1.number}
    }
    @discardableResult func add(_ settings: EffectSettings) throws -> SavedEffectPreset {
        // Re-read before appending so another app launch's completed saves
        // aren't replaced by this view's older list. Never overwrite a bad file.
        var next=try url.map{try Self.read($0)} ?? presets
        let number=(next.last?.number ?? 0)+1
        guard number<Int.max else { throw ArchiveError.invalid }
        let saved=SavedEffectPreset(number:number,settings:settings);next.append(saved)
        if let url=url {
            let encoder=PropertyListEncoder();encoder.outputFormat = .xml
            let data=try encoder.encode(Archive(presets:next))
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:url,options:.atomic)
        }
        presets=next;loadError=nil;return saved
    }
}

struct EffectPresetPicker {
    enum Choice: Equatable {
        case standard,add,saved(Int)
        var title: String {
            switch self { case .standard:return "Default";case .add:return "Add";case .saved(let n):return String(n) }
        }
    }
    private(set) var selection=Choice.standard
    private var observed=EffectSettings()
    mutating func observe(_ settings: EffectSettings) {
        if settings != observed { selection = .add;observed=settings }
    }
    mutating func applied(_ settings: EffectSettings,as choice: Choice) { observed=settings;selection=choice }
    mutating func cycle(_ direction: Int,presets: [SavedEffectPreset]) {
        let choices:[Choice]=[.standard,.add]+presets.map{.saved($0.number)}
        let index=choices.firstIndex(of:selection) ?? 0
        selection=choices[(index+direction+choices.count)%choices.count]
    }
}
