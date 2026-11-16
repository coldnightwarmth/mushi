/// Futari-only active-low cabinet wiring. Keep this out of the shared frontend:
/// its second/third physical buttons differ from ESP Ra.De's attack semantics.
struct FutariInputPorts: Equatable {
    let c: UInt8
    let d: UInt8

    init(_ buttons: ArcadeButtons) {
        var c: UInt8 = 0, d: UInt8 = 0
        for (action, mask): (ArcadeButtons, UInt8) in [
            (.up, 1), (.down, 2), (.left, 4), (.right, 8),
            (.shot, 0x10), (.secondary, 0x40), (.special, 0x20)
        ] where buttons.contains(action) { d |= mask }
        if buttons.contains(.start) { c |= 0x10 }
        if buttons.contains(.credit) { c |= 4 }
        self.c = ~c; self.d = ~d
    }
}
