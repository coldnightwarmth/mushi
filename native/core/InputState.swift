import Foundation

/// Translation of Futari 1.5 input records at 0x0c05c468 and 0x0c05c4ac.
/// The sampler supplies +0x0c; the main-loop service generates edges/repeats.
/// This code executes directly on the Mac CPU and has no emulator dependency.
struct InputState {
    static let byteCount = 0x88
    static let repeatMasks: [UInt32] = [1, 2, 4, 8, 0x10, 0x20, 0x40, 0x80, 0x8000]
    var bytes: [UInt8]

    init(bytes: [UInt8] = [UInt8](repeating: 0, count: byteCount)) {
        precondition(bytes.count == Self.byteCount)
        self.bytes = bytes
    }

    func word(_ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(bytes[offset + $1]) }
    }

    mutating func put(_ offset: Int, _ value: UInt32) {
        for n in 0..<4 { bytes[offset + n] = UInt8(truncatingIfNeeded: value >> (24 - n * 8)) }
    }

    /// 0x0c05c4f0. +0x10 (edge latch) is deliberately NOT reset by the original.
    mutating func initialize() {
        for base in [0, 0x44] {
            for offset in [0, 4, 8, 12, 20] + Array(stride(from: 32, through: 64, by: 4)) {
                put(base + offset, 0)
            }
            put(base + 0x18, 16)
            put(base + 0x1c, 4)
        }
    }

    /// 0x0c05c62c. Counters are u32 bit patterns with wrapping decrement.
    mutating func advance() {
        for base in [0, 0x44] {
            let previous = word(base), current = word(base + 0x0c)
            put(base, current)
            put(base + 0x10, current & ~previous)
            var repeated: UInt32 = 0
            for (index, mask) in Self.repeatMasks.enumerated() {
                let at = base + 0x20 + index * 4
                if current & mask == 0 {
                    put(at, 0)
                } else if word(at) == 0 {
                    repeated |= mask
                    put(at, word(base + 0x18))
                } else {
                    let next = word(at) &- 1
                    put(at, next)
                    if next == 0 {
                        repeated |= mask
                        put(at, word(base + 0x1c))
                    }
                }
            }
            put(base + 0x14, repeated)
        }
    }

    /// The original treats every nonzero selector as player two.
    func held(player: UInt32) -> UInt32 { word((player == 0 ? 0 : 0x44) + 0x0c) }
    func pressed(player: UInt32) -> UInt32 { word((player == 0 ? 0 : 0x44) + 0x10) }
    func repeating(player: UInt32) -> UInt32 { word((player == 0 ? 0 : 0x44) + 0x14) }

    /// 0x0c05caa0: enqueue a cabinet output pulse, consumed by the IRQ sampler.
    mutating func enqueueOutput(player: UInt32) {
        let at = (player == 0 ? 0 : 0x44) + 8
        put(at, word(at) &+ 1)
    }
}
