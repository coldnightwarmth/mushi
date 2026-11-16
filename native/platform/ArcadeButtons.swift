/// Game-independent actions. These values match ESP Ra.De's logical input mask,
/// while each game adapter owns its original cabinet wiring and input clocks.
struct ArcadeButtons: OptionSet {
    let rawValue: UInt16
    static let up = Self(rawValue: 1)
    static let down = Self(rawValue: 2)
    static let left = Self(rawValue: 4)
    static let right = Self(rawValue: 8)
    static let shot = Self(rawValue: 16)
    static let secondary = Self(rawValue: 32)
    static let special = Self(rawValue: 64)
    static let start = Self(rawValue: 128)
    static let credit = Self(rawValue: 256)
}
