// Native Launch Services entry point for the locally bundled reference runtime.
// Game execution remains MAME; this launcher handles packaging and startup errors.
import AppKit
import Darwin

private let files = FileManager.default

private func fail(_ message: String) -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    application.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "Futari couldn’t start"
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.runModal()
    exit(1)
}

private func seedMissingFiles(from source: URL, to destination: URL) throws {
    guard files.fileExists(atPath: source.path) else { return }
    try files.createDirectory(at: destination, withIntermediateDirectories: true)
    for name in try files.contentsOfDirectory(atPath: source.path) {
        let input = source.appendingPathComponent(name)
        let output = destination.appendingPathComponent(name)
        var directory: ObjCBool = false
        _ = files.fileExists(atPath: input.path, isDirectory: &directory)
        if directory.boolValue {
            try seedMissingFiles(from: input, to: output)
        } else if !files.fileExists(atPath: output.path) {
            try files.copyItem(at: input, to: output)
        }
    }
}

let bundle = Bundle.main
guard let resources = bundle.resourceURL else {
    fail("This app is missing its Resources folder. Rebuild or restore the app.")
}
let runtime = bundle.bundleURL.appendingPathComponent("Contents/MacOS/mame")
let roms = resources.appendingPathComponent("roms")
let rom = roms.appendingPathComponent("futari15.zip")
guard files.isExecutableFile(atPath: runtime.path) else {
    fail("The game runtime is missing from this app. Rebuild or restore the app.")
}
guard files.isReadableFile(atPath: rom.path) else {
    fail("The Futari game data is missing from this app. Rebuild it using your futari15.zip archive.")
}

do {
    let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                               appropriateFor: nil, create: true)
    let state = support.appendingPathComponent("Mushi/Reference", isDirectory: true)
    try seedMissingFiles(from: resources.appendingPathComponent("seed-state"), to: state)
    for folder in ["cfg", "nvram", "snap", "ini", "sta", "inp", "diff"] {
        try files.createDirectory(at: state.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    var arguments = [runtime.path, "futari15", "-rompath", roms.path,
                     "-window", "-resolution", "720x960", "-nofilter", "-keepaspect",
                     "-sound", "sdl", "-skip_gameinfo",
                     "-cfg_directory", state.appendingPathComponent("cfg").path,
                     "-nvram_directory", state.appendingPathComponent("nvram").path,
                     "-snapshot_directory", state.appendingPathComponent("snap").path,
                     "-inipath", state.appendingPathComponent("ini").path,
                     "-state_directory", state.appendingPathComponent("sta").path,
                     "-input_directory", state.appendingPathComponent("inp").path,
                     "-diff_directory", state.appendingPathComponent("diff").path]
    let extra = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
    if extra.contains("--diagnose") {
        let report: [String: Any] = ["runtime": runtime.path, "rom": rom.path,
                                    "state": state.path, "arguments": arguments]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        exit(0)
    }
    arguments.append(contentsOf: extra)
    guard files.changeCurrentDirectoryPath(state.path) else {
        fail("The save folder could not be opened: \(state.path)")
    }
    let log = state.appendingPathComponent("app.log")
    let descriptor = open(log.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
    guard descriptor >= 0 else {
        fail("The startup log could not be written: \(log.path)")
    }
    _ = dup2(descriptor, STDOUT_FILENO)
    _ = dup2(descriptor, STDERR_FILENO)
    if descriptor > STDERR_FILENO { close(descriptor) }
    let stamp = "\nFutari native launcher v2 — \(Date())\n"
    FileHandle.standardError.write(Data(stamp.utf8))
    // Replace this process so the game retains the app's normal foreground identity.
    // All non-system dependencies resolve inside the bundle, without DYLD overrides.
    let strings = arguments.map { strdup($0) }
    var argv = strings + [nil]
    argv.withUnsafeMutableBufferPointer { buffer in
        _ = execv(runtime.path, buffer.baseAddress!)
    }
    let reason = String(cString: strerror(errno))
    for string in strings { free(string) }
    fail("The game runtime could not start: \(reason)\n\nDetails: \(log.path)")
} catch {
    fail("The app could not prepare its save folder.\n\n\(error.localizedDescription)")
}
