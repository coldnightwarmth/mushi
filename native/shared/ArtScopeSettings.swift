import Foundation

enum ArtGroup: CaseIterable {
    case background, player, enemies, otherActors
    var mask: ArtGroupMask {
        switch self {
        case .background:return .background
        case .player:return .player
        case .enemies:return .enemies
        case .otherActors:return .otherActors
        }
    }
    // Retain the two historical protection bits and add enemy ownership.
    var echoTag: UInt8 {
        switch self { case .background:return 0;case .player:return 12;case .enemies:return 20;case .otherActors:return 4 }
    }
    static func fromEchoTag(_ tag: UInt8)->ArtGroup {
        if tag&8 != 0 { return .player }
        if tag&16 != 0 { return .enemies }
        return tag&4 != 0 ? .otherActors:.background
    }
}
struct ArtGroupMask: OptionSet, Hashable {
    let rawValue: UInt8
    static let background=Self(rawValue:1),player=Self(rawValue:2),enemies=Self(rawValue:4),otherActors=Self(rawValue:8)
    static let all: Self=[.background,.player,.enemies,.otherActors]
}
struct ArtRenderPlan {
    var groups: ArtGroupMask
    let options: ArtOptions
}

/// The menu selects which bank to edit; every bank remains in the composition.
/// Only enabled choices override broader choices. An effect has exactly one
/// resolved variant per group, never a chain of broad and narrow applications.
struct ArtScopeSettings: Equatable {
    static let editingScopes: [ArtOptions.Scope]=[.on,.background,.nonPlayer,.player,.enemies]
    private(set) var selected=ArtOptions.Scope.on
    private var lastEditing=ArtOptions.Scope.on
    var editingScope: ArtOptions.Scope { lastEditing }
    private var configurations=[ArtOptions.Scope:ArtOptions]()
    var current: ArtOptions {
        get {
            var result=configuration(for:selected == .off ? lastEditing:selected)
            result.scope=selected;return result
        }
        set {
            let target=newValue.scope == .off ? lastEditing:newValue.scope
            var value=newValue;value.scope=target
            set(value,for:target);select(newValue.scope)
        }
    }
    func configuration(for scope: ArtOptions.Scope)->ArtOptions {
        if let value=configurations[scope] { return value }
        var value=ArtOptions();value.scope=scope;return value
    }
    mutating func set(_ options: ArtOptions,for scope: ArtOptions.Scope) {
        guard scope != .off else { return }
        var value=options;value.scope=scope
        var empty=ArtOptions();empty.scope=scope
        if value==empty { configurations.removeValue(forKey:scope) }
        else { configurations[scope]=value }
    }
    mutating func select(_ scope: ArtOptions.Scope) {
        selected=scope;if scope != .off { lastEditing=scope }
    }
    mutating func cycle(_ direction: Int) {
        let choices=ArtOptions.Scope.allCases,index=choices.firstIndex(of:selected)!
        select(choices[(index+direction+choices.count)%choices.count])
    }
    func resolved(for group: ArtGroup)->ArtOptions {
        var result=ArtOptions()
        guard selected != .off else { return result }
        let scopes: [ArtOptions.Scope]
        switch group {
        case .background:scopes=[.on,.nonPlayer,.background]
        case .player:scopes=[.on,.player]
        case .enemies:scopes=[.on,.nonPlayer,.enemies]
        case .otherActors:scopes=[.on,.nonPlayer]
        }
        for scope in scopes {
            let options=configuration(for:scope)
            guard options.values.contains(where:{$0>0}) else { continue }
            for effect in ArtEffect.allCases where options.values[effect.rawValue]>0 {
                result[effect]=options.values[effect.rawValue]
            }
            result.memoryIndex=options.memoryIndex
        }
        return result
    }
    var plans: [ArtRenderPlan] {
        var result=[ArtRenderPlan]()
        for group in ArtGroup.allCases {
            let options=resolved(for:group)
            if let index=result.firstIndex(where:{$0.options==options}) { result[index].groups.insert(group.mask) }
            else { result.append(ArtRenderPlan(groups:group.mask,options:options)) }
        }
        return result
    }
    var active: Bool { selected != .off && configurations.values.contains{$0.active} }
    var singleProtectedScope: ArtOptions? {
        let enabled=configurations.values.filter{$0.active}
        guard selected != .off,enabled.count==1,enabled[0].protectsActors else { return nil }
        return enabled[0]
    }
    func uses(_ effect: ArtEffect)->Bool { selected != .off && configurations.values.contains{$0[effect]>0} }
    var menuHelp: String {
        let group: String
        switch selected {
        case .off:return "Pause other effects. Image trails keep running. Choose a group to resume all saved group settings."
        case .on:group="Yes sets effects for the whole scene."
        case .background:group="Bkg sets effects for scenery, debris and visual FX."
        case .nonPlayer:group="Non-player sets effects for everything except players and their weapons."
        case .player:group="Player sets effects for you, wingmates and friendly weapons."
        case .enemies:group="Enemies sets effects for live enemies and hostile bullets."
        }
        return group+" Echoes follow their source. Groups run together; enabled specific settings override broader ones."
    }
    var optionHelp: String {
        selected == .on ? "Editing Yes, the whole-scene settings.":"Editing \(selected == .off ? lastEditing.title:selected.title). Off leaves broader settings active."
    }
}
