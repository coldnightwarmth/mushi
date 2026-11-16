import Foundation

/// ESP Ra.De physical key layout, mapped to game-independent actions.
/// App commands belong to the native host; they never become arcade inputs.
enum MacCommand: Equatable {
    case pause, menu, mute, title, restart, filtering
}

struct MacControls {
    private var held = Set<UInt16>()
    private var pending: ArcadeButtons = []

    static func binding(_ key: UInt16) -> ArcadeButtons {
        switch key {
        case 126, 13: return .up
        case 125, 1:  return .down
        case 123, 0:  return .left
        case 124, 2:  return .right
        case 38:      return .shot // J
        case 40, 7:   return .secondary // K / X
        case 37:      return .special // L
        case 36:      return .start // Return
        case 42:      return .credit // Backslash
        default:      return []
        }
    }

    var zoomHeld: Bool { held.contains(6) } // Z is reserved for camera zoom.

    mutating func keyDown(_ key: UInt16, isRepeat: Bool = false) -> MacCommand? {
        let command: MacCommand?
        switch key {
        case 49: command = .pause
        case 48: command = .menu
        case 46: command = .mute
        case 53: command = .title
        case 15: command = .restart
        case 35: command = .filtering
        default: command = nil
        }
        if let command = command {
            if isRepeat { return nil }
            if [.pause, .menu, .title, .restart].contains(command) { clear() }
            return command
        }
        if held.insert(key).inserted {
            pending.formUnion(Self.binding(key))
        }
        return nil
    }

    mutating func keyUp(_ key: UInt16) { held.remove(key) }

    mutating func nextFrame() -> ArcadeButtons {
        var buttons = pending
        for key in held {
            buttons.formUnion(Self.binding(key))
        }
        pending = []
        return buttons
    }

    /// Focus loss, title return and menu transitions must release every alias.
    mutating func clear() { held.removeAll(); pending = [] }
}
