import Foundation

@main struct InputVerification {
    static func main() throws {
        var controls = MacControls()
        _ = controls.keyDown(13); _ = controls.keyDown(126)
        precondition(controls.nextFrame() == .up)
        controls.keyUp(13)
        precondition(controls.nextFrame() == .up, "Releasing W must preserve held Up")
        controls.keyUp(126)
        precondition(controls.nextFrame().isEmpty)
        _ = controls.keyDown(42); controls.keyUp(42)
        precondition(controls.nextFrame() == .credit, "Sub-frame credit taps must survive")
        precondition(controls.nextFrame().isEmpty, "A tap must not stick")
        for (keys, value) in [([UInt16(38)], UInt8(0xef)), ([40, 7], 0xbf), ([37], 0xdf)] {
            for key in keys { _ = controls.keyDown(key) }
            precondition(FutariInputPorts(controls.nextFrame()).d == value)
            controls.clear()
        }
        for key in [UInt16(6), 18, 8] { _ = controls.keyDown(key) }
        precondition(controls.zoomHeld && controls.nextFrame().isEmpty, "Z, 1 and C must not fire/start")
        for (key, command) in [(UInt16(49), MacCommand.pause), (48, .menu), (46, .mute), (53, .title), (15, .restart), (35, .filtering)] {
            precondition(controls.keyDown(key) == command)
            precondition(controls.keyDown(key, isRepeat: true) == nil)
        }
        _ = controls.keyDown(38); controls.clear()
        precondition(controls.nextFrame().isEmpty, "Focus loss must clear held and pending input")
        precondition(FutariInputPorts([.start, .credit]).c == 0xeb)
        print("PASS: ESP Ra.De controls, aliases, quick taps, focus reset, app-command repeat suppression")
        let args = CommandLine.arguments
        guard args.count == 3 else { return }
        let cases = Array(try Data(contentsOf: URL(fileURLWithPath: args[1])))
        let expected = Array(try Data(contentsOf: URL(fileURLWithPath: args[2])))
        let stride = InputState.byteCount + 8, outputStride = InputState.byteCount + 4
        precondition(cases.count % stride == 0)
        let count = cases.count / stride
        precondition(expected.count == count * outputStride)
        func read(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(bytes[offset + $1]) }
        }
        for index in 0..<count {
            let start = index * stride, target = index * outputStride
            let entry = read(cases, start), argument = read(cases, start + 4)
            var state = InputState(bytes: Array(cases[(start + 8)..<(start + stride)]))
            var result: UInt32?
            switch entry {
            case 0x0c05c4f0: state.initialize()
            case 0x0c05c62c: state.advance()
            case 0x0c05ca18: result = state.held(player: argument)
            case 0x0c05ca30: result = state.pressed(player: argument)
            case 0x0c05ca48: result = state.repeating(player: argument)
            case 0x0c05caa0: state.enqueueOutput(player: argument)
            default: fatalError("Untranslated test entry")
            }
            precondition(state.bytes == Array(expected[(target + 4)..<(target + outputStride)]), "State differs in case \(index), entry \(String(entry, radix: 16))")
            if let result = result { precondition(result == read(expected, target), "Return register differs in case \(index)") }
        }
        print("PASS: \(count) native input cases match original SH-3 record bytes and query returns")
    }
}
