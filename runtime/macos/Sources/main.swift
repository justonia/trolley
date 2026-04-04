import AppKit
import CGhostty
import CTrolley

// ---------------------------------------------------------------------------
// Global state (needed by C callbacks which don't carry user context)
// ---------------------------------------------------------------------------
var gWindow: NSWindow?
var gSurface: ghostty_surface_t?
var gApp: ghostty_app_t?
var gWindowConfig = TrolleyGuiConfig(
    initial_width: 0, initial_height: 0, resizable: -1,
    min_width: 0, min_height: 0, max_width: 0, max_height: 0,
    win_precise_timer: 0,
    screenshot_path: nil,
    inject_pid_variable: nil,
    pid_file: nil,
    text_dump_path: nil,
    text_dump_format: 0,
    command_file: nil,
    command_format: 0
)

// ---------------------------------------------------------------------------
// Modifier translation
// ---------------------------------------------------------------------------
func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
    if flags.contains(.shift)   { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option)  { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock){ mods |= GHOSTTY_MODS_CAPS.rawValue }
    return ghostty_input_mods_e(mods)
}

// ---------------------------------------------------------------------------
// Ghostty runtime callbacks
// ---------------------------------------------------------------------------
func wakeupCallback(_ userdata: UnsafeMutableRawPointer?) {
    DispatchQueue.main.async {
        guard let app = gApp else { return }
        ghostty_app_tick(app)
    }
}

func actionCallback(
    _ app: ghostty_app_t?,
    _ target: ghostty_target_s,
    _ action: ghostty_action_s
) -> Bool {
    switch action.tag {
    case GHOSTTY_ACTION_SET_TITLE:
        let title = String(cString: action.action.set_title.title)
        gWindow?.title = title
        return true

    case GHOSTTY_ACTION_QUIT:
        NSApp.terminate(nil)
        return true

    case GHOSTTY_ACTION_CLOSE_WINDOW:
        gWindow?.close()
        return true

    case GHOSTTY_ACTION_INITIAL_SIZE:
        let size = action.action.initial_size
        gWindow?.setContentSize(NSSize(
            width: CGFloat(size.width),
            height: CGFloat(size.height)
        ))
        return true

    case GHOSTTY_ACTION_SIZE_LIMIT:
        let limits = action.action.size_limit
        // Only override if the manifest didn't already set them.
        if gWindowConfig.min_width == 0 && limits.min_width > 0 {
            gWindowConfig.min_width = limits.min_width
        }
        if gWindowConfig.min_height == 0 && limits.min_height > 0 {
            gWindowConfig.min_height = limits.min_height
        }
        if gWindowConfig.max_width == 0 && limits.max_width > 0 {
            gWindowConfig.max_width = limits.max_width
        }
        if gWindowConfig.max_height == 0 && limits.max_height > 0 {
            gWindowConfig.max_height = limits.max_height
        }
        // Apply the (possibly merged) values
        gWindow?.minSize = NSSize(
            width: gWindowConfig.min_width > 0 ? CGFloat(gWindowConfig.min_width) : 0,
            height: gWindowConfig.min_height > 0 ? CGFloat(gWindowConfig.min_height) : 0
        )
        gWindow?.maxSize = NSSize(
            width: gWindowConfig.max_width > 0 ? CGFloat(gWindowConfig.max_width) : CGFloat.greatestFiniteMagnitude,
            height: gWindowConfig.max_height > 0 ? CGFloat(gWindowConfig.max_height) : CGFloat.greatestFiniteMagnitude
        )
        return true

    case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
        return true

    default:
        return false
    }
}

func readClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ loc: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
) -> Bool {
    guard let surface = gSurface else { return false }
    if let str = NSPasteboard.general.string(forType: .string) {
        str.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
        return true
    }
    return false
}

func confirmReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ content: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?,
    _ request: ghostty_clipboard_request_e
) {
    readClipboardCallback(userdata, GHOSTTY_CLIPBOARD_STANDARD, state)
}

func writeClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ loc: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ len: Int,
    _ confirm: Bool
) {
    guard let content, len > 0 else { return }
    let data = String(cString: content[0].data)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(data, forType: .string)
}

func closeSurfaceCallback(_ userdata: UnsafeMutableRawPointer?, _ processAlive: Bool) {
    NSApp.terminate(nil)
}

// ---------------------------------------------------------------------------
// Path resolution — all resources are next to the executable
// ---------------------------------------------------------------------------
func getExeDir() -> String {
    let exe = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
    return (exe as NSString).deletingLastPathComponent
}

func getBundledPath(_ filename: String) -> String? {
    // Check Resources dir first (macOS .app bundle)
    if let resourcePath = Bundle.main.resourcePath {
        let path = (resourcePath as NSString).appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: path) { return path }
    }
    // Fall back to exe dir (flat layout / development)
    let path = (getExeDir() as NSString).appendingPathComponent(filename)
    return FileManager.default.fileExists(atPath: path) ? path : nil
}

// ---------------------------------------------------------------------------
// Font registration via CoreText
// ---------------------------------------------------------------------------
import CoreText

func registerBundledFonts() {
    let fm = FileManager.default

    // Check Resources dir first (macOS .app bundle), fall back to exe dir
    var fontsDir = (getExeDir() as NSString).appendingPathComponent("fonts")
    if let resourcePath = Bundle.main.resourcePath {
        let resourceFonts = (resourcePath as NSString).appendingPathComponent("fonts")
        if fm.fileExists(atPath: resourceFonts) { fontsDir = resourceFonts }
    }

    guard fm.fileExists(atPath: fontsDir) else { return }
    guard let files = try? fm.contentsOfDirectory(atPath: fontsDir) else { return }

    for file in files {
        let ext = (file as NSString).pathExtension.lowercased()
        guard ext == "ttf" || ext == "otf" else { continue }

        let fontPath = (fontsDir as NSString).appendingPathComponent(file)
        let fontURL = URL(fileURLWithPath: fontPath) as CFURL
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(fontURL, .process, &error) {
            fputs("trolley: warning: failed to register font \(file)\n", stderr)
        }
    }
}

// ---------------------------------------------------------------------------
// Environment loading
// ---------------------------------------------------------------------------

/// Read the bundled `environment` file and call setenv for each KEY=VALUE line.
/// Skips blank lines and lines starting with `#`.
func loadBundledEnvironment() {
    guard let path = getBundledPath("environment") else { return }
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
    for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
        let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
        let value = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
        setenv(key, value, 1)
    }
}

// ---------------------------------------------------------------------------
// TrolleyView — NSView subclass that hosts the ghostty Metal surface
// ---------------------------------------------------------------------------
class TrolleyView: NSView, NSTextInputClient {
    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    // Two-phase key input state
    private var pendingKeyEvent: ghostty_input_key_s?
    private var keyTextAccumulator: [String]?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Resize & DPI

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface = gSurface else { return }
        let backed = convertToBacking(newSize)
        if backed.width > 0 && backed.height > 0 {
            ghostty_surface_set_size(surface, UInt32(backed.width), UInt32(backed.height))
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface = gSurface else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        gSurface.map { ghostty_surface_set_focus($0, true) }
        return true
    }

    override func resignFirstResponder() -> Bool {
        gSurface.map { ghostty_surface_set_focus($0, false) }
        return true
    }

    // MARK: - Keyboard input

    override func keyDown(with event: NSEvent) {
        guard let surface = gSurface else { return }
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        // Two-phase input: first send raw key, then use interpretKeyEvents
        // to get composed text from the input method.
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        interpretKeyEvents([event])

        if let texts = keyTextAccumulator, !texts.isEmpty {
            for text in texts {
                sendKey(action, event: event, text: text)
            }
        } else {
            sendKey(action, event: event, text: event.characters)
        }
    }

    override func keyUp(with event: NSEvent) {
        sendKey(GHOSTTY_ACTION_RELEASE, event: event, text: nil)
    }

    override func flagsChanged(with event: NSEvent) {
        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }

        let mods = ghosttyMods(event.modifierFlags)
        let action = (mods.rawValue & mod != 0) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        sendKey(action, event: event, text: nil)
    }

    private func sendKey(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        text: String?
    ) {
        guard let surface = gSurface else { return }

        var key_ev = ghostty_input_key_s()
        key_ev.action = action
        key_ev.keycode = UInt32(event.keyCode)
        key_ev.mods = ghosttyMods(event.modifierFlags)
        key_ev.consumed_mods = ghosttyMods(
            event.modifierFlags.subtracting([.control, .command])
        )
        key_ev.composing = false
        key_ev.text = nil
        key_ev.unshifted_codepoint = 0

        // Set unshifted codepoint
        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                key_ev.unshifted_codepoint = codepoint.value
            }
        }

        if let text, !text.isEmpty,
           let first = text.utf8.first, first >= 0x20 {
            text.withCString { ptr in
                key_ev.text = ptr
                _ = ghostty_surface_key(surface, key_ev)
            }
        } else {
            _ = ghostty_surface_key(surface, key_ev)
        }
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let chars: String
        switch string {
        case let s as NSAttributedString: chars = s.string
        case let s as String: chars = s
        default: return
        }

        keyTextAccumulator?.append(chars)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }
    func characterIndex(for point: NSPoint) -> Int { 0 }

    override func doCommand(by selector: Selector) {
        // Prevents NSBeep for unhandled key equivalents
    }

    // MARK: - Mouse input

    override func mouseDown(with event: NSEvent) {
        guard let surface = gSurface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, ghosttyMods(event.modifierFlags))
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface = gSurface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, ghosttyMods(event.modifierFlags))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface = gSurface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, ghosttyMods(event.modifierFlags))
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface = gSurface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, ghosttyMods(event.modifierFlags))
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let surface = gSurface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_MIDDLE, ghosttyMods(event.modifierFlags))
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let surface = gSurface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_MIDDLE, ghosttyMods(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface = gSurface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, Double(pos.x), Double(frame.height - pos.y), ghosttyMods(event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface = gSurface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas
        if precision {
            x *= 2
            y *= 2
        }
        var mods: Int32 = 0
        if precision { mods |= 0b0000_0001 }
        // Momentum phase in bits 1-3
        let momentum: UInt8
        switch event.momentumPhase {
        case .began: momentum = 1
        case .stationary: momentum = 2
        case .changed: momentum = 3
        case .ended: momentum = 4
        case .cancelled: momentum = 5
        case .mayBegin: momentum = 6
        default: momentum = 0
        }
        mods |= Int32(momentum) << 1
        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }
}

// ---------------------------------------------------------------------------
// Command file support
// ---------------------------------------------------------------------------

/// Key name to escape sequence map (VT/xterm normal cursor mode).
let commandKeyMap: [String: String] = [
    "enter": "\r",
    "tab": "\t",
    "escape": "\u{1b}",
    "backspace": "\u{7f}",
    "space": " ",
    "arrow_up": "\u{1b}[A", "up": "\u{1b}[A",
    "arrow_down": "\u{1b}[B", "down": "\u{1b}[B",
    "arrow_right": "\u{1b}[C", "right": "\u{1b}[C",
    "arrow_left": "\u{1b}[D", "left": "\u{1b}[D",
    "home": "\u{1b}[H",
    "end": "\u{1b}[F",
    "page_up": "\u{1b}[5~",
    "page_down": "\u{1b}[6~",
    "insert": "\u{1b}[2~",
    "delete": "\u{1b}[3~",
    "f1": "\u{1b}OP", "f2": "\u{1b}OQ", "f3": "\u{1b}OR", "f4": "\u{1b}OS",
    "f5": "\u{1b}[15~", "f6": "\u{1b}[17~", "f7": "\u{1b}[18~", "f8": "\u{1b}[19~",
    "f9": "\u{1b}[20~", "f10": "\u{1b}[21~", "f11": "\u{1b}[23~", "f12": "\u{1b}[24~",
    "ctrl+a": "\u{01}", "ctrl+b": "\u{02}", "ctrl+c": "\u{03}", "ctrl+d": "\u{04}",
    "ctrl+e": "\u{05}", "ctrl+f": "\u{06}", "ctrl+g": "\u{07}", "ctrl+h": "\u{08}",
    "ctrl+k": "\u{0b}", "ctrl+l": "\u{0c}", "ctrl+n": "\u{0e}", "ctrl+o": "\u{0f}",
    "ctrl+p": "\u{10}", "ctrl+q": "\u{11}", "ctrl+r": "\u{12}", "ctrl+s": "\u{13}",
    "ctrl+t": "\u{14}", "ctrl+u": "\u{15}", "ctrl+v": "\u{16}", "ctrl+w": "\u{17}",
    "ctrl+x": "\u{18}", "ctrl+y": "\u{19}", "ctrl+z": "\u{1a}",
]

/// Keys that change under DECCKM (application cursor key mode).
let commandAppCursorOverrides: [String: String] = [
    "arrow_up": "\u{1b}OA", "up": "\u{1b}OA",
    "arrow_down": "\u{1b}OB", "down": "\u{1b}OB",
    "arrow_right": "\u{1b}OC", "right": "\u{1b}OC",
    "arrow_left": "\u{1b}OD", "left": "\u{1b}OD",
    "home": "\u{1b}OH",
    "end": "\u{1b}OF",
]

/// Resolve a key name to its escape sequence, respecting application cursor mode.
func resolveCommandKey(_ name: String, appCursor: Bool) -> String? {
    if appCursor, let seq = commandAppCursorOverrides[name] { return seq }
    return commandKeyMap[name]
}

struct TrolleyCommand {
    enum Tag { case text, key, wait, screenshot, textDump }
    let tag: Tag
    let data: String
    let format: UInt8  // for text_dump: 0=plain, 1=vt, 2=html
}

/// Parse a single JSON line into a TrolleyCommand.
/// Aborts the process if the line cannot be parsed — partial execution of a
/// command batch would leave the controlling program in an undefined state.
func parseCommandLine(_ line: String) -> TrolleyCommand {
    guard let jsonData = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let typeStr = obj["type"] as? String else {
        fputs("trolley: command: failed to parse line: \(line)\n", stderr)
        exit(1)
    }
    let data = obj["data"] as? String ?? ""
    let tag: TrolleyCommand.Tag
    switch typeStr {
    case "text": tag = .text
    case "key": tag = .key
    case "wait": tag = .wait
    case "screenshot": tag = .screenshot
    case "text_dump": tag = .textDump
    default:
        fputs("trolley: command: failed to parse line: \(line)\n", stderr)
        exit(1)
    }
    var format: UInt8 = 0
    if tag == .textDump, let fmtStr = obj["format"] as? String {
        switch fmtStr {
        case "vt": format = 1
        case "html": format = 2
        default: format = 0
        }
    }
    return TrolleyCommand(tag: tag, data: data, format: format)
}

/// Resolve the command format from TROLLEY_COMMAND_FORMAT env var, falling back to config.
func resolvedCommandFormat() -> UInt8 {
    if let envVal = ProcessInfo.processInfo.environment["TROLLEY_COMMAND_FORMAT"], !envVal.isEmpty {
        return envVal == "bare" ? 1 : 0
    }
    return gWindowConfig.command_format
}

/// Load and execute commands from the command file.
/// Waits are handled via recursive DispatchQueue.main.asyncAfter.
func loadAndExecuteCommandFile(path: String) {
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
        fputs("trolley: command: failed to read \(path)\n", stderr)
        exit(1)
    }
    // Truncate the file to zero bytes (signals "read acknowledged").
    // The file will be deleted once all commands finish executing.
    FileManager.default.createFile(atPath: path, contents: Data())

    let format = resolvedCommandFormat()
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
    var commands: [TrolleyCommand] = []
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        // In bare format, wrap each line with { } before parsing.
        let jsonLine = format == 1 ? "{\(trimmed)}" : trimmed
        commands.append(parseCommandLine(jsonLine))
    }
    executeCommands(commands, index: 0, commandFilePath: path)
}

/// Maximum time (seconds) to wait for a screenshot file to appear.
let screenshotTimeoutSeconds: Double = 2.0

/// Check if a file exists with size > 0.
func fileExistsWithSize(_ path: String) -> Bool {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attrs[.size] as? UInt64 else { return false }
    return size > 0
}

/// Poll for a screenshot file, then continue executing commands.
func waitForScreenshot(path: String, deadline: Date, commands: [TrolleyCommand], index: Int, commandFilePath: String?) {
    if fileExistsWithSize(path) {
        fputs("trolley: command: screenshot ready \(path)\n", stderr)
        executeCommands(commands, index: index, commandFilePath: commandFilePath)
        return
    }
    if Date() >= deadline {
        fputs("trolley: command: screenshot timed out, aborting\n", stderr)
        exit(1)
    }
    // Poll again in 50ms.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        waitForScreenshot(path: path, deadline: deadline, commands: commands, index: index, commandFilePath: commandFilePath)
    }
}

/// Execute commands sequentially, deferring on wait and screenshot commands.
/// When all commands are done, deletes the command file (signals "execution finished").
func executeCommands(_ commands: [TrolleyCommand], index: Int, commandFilePath: String?) {
    guard index < commands.count else {
        // All commands finished — delete the command file.
        if let filePath = commandFilePath {
            try? FileManager.default.removeItem(atPath: filePath)
        }
        return
    }
    let cmd = commands[index]

    if cmd.tag == .wait {
        let seconds = Double(cmd.data) ?? 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            executeCommands(commands, index: index + 1, commandFilePath: commandFilePath)
        }
        return
    }

    executeSingleCommand(cmd)

    // If it was a screenshot, wait for the file before continuing.
    if cmd.tag == .screenshot {
        let path: String
        if !cmd.data.isEmpty {
            path = cmd.data
        } else if let configPath = gWindowConfig.screenshot_path {
            path = String(cString: configPath)
        } else {
            // No path — can't wait, just continue.
            if index + 1 < commands.count {
                executeCommands(commands, index: index + 1, commandFilePath: commandFilePath)
            } else if let filePath = commandFilePath {
                try? FileManager.default.removeItem(atPath: filePath)
            }
            return
        }
        let deadline = Date().addingTimeInterval(screenshotTimeoutSeconds)
        waitForScreenshot(path: path, deadline: deadline, commands: commands, index: index + 1, commandFilePath: commandFilePath)
        return
    }

    // Continue to next command immediately.
    if index + 1 < commands.count {
        executeCommands(commands, index: index + 1, commandFilePath: commandFilePath)
    } else if let filePath = commandFilePath {
        try? FileManager.default.removeItem(atPath: filePath)
    }
}

func executeSingleCommand(_ cmd: TrolleyCommand) {
    guard let surface = gSurface else { return }
    let appCursor = ghostty_surface_cursor_key_mode(surface)
    let modeStr = appCursor ? "app" : "normal"
    switch cmd.tag {
    case .text:
        fputs("trolley: command: text \"\(cmd.data)\" (cursor=\(modeStr))\n", stderr)
        cmd.data.withCString { ptr in
            ghostty_surface_write_pty(surface, ptr, cmd.data.utf8.count)
        }
    case .key:
        guard let seq = resolveCommandKey(cmd.data, appCursor: appCursor) else {
            fputs("trolley: command: unknown key \"\(cmd.data)\" (cursor=\(modeStr))\n", stderr)
            return
        }
        fputs("trolley: command: key \"\(cmd.data)\" -> \(seq.utf8.count) bytes (cursor=\(modeStr))\n", stderr)
        seq.withCString { ptr in
            ghostty_surface_write_pty(surface, ptr, seq.utf8.count)
        }
    case .screenshot:
        let screenshotPath: String = !cmd.data.isEmpty ? cmd.data :
            (gWindowConfig.screenshot_path.map { String(cString: $0) } ?? "")
        // Delete existing file so we can detect the new one.
        try? FileManager.default.removeItem(atPath: screenshotPath)
        fputs("trolley: command: screenshot \"\(screenshotPath)\" (cursor=\(modeStr)) waiting...\n", stderr)
        if !cmd.data.isEmpty {
            cmd.data.withCString { ptr in
                ghostty_surface_screenshot(surface, ptr)
            }
        } else if let path = gWindowConfig.screenshot_path {
            ghostty_surface_screenshot(surface, path)
        }
    case .textDump:
        fputs("trolley: command: text_dump \"\(cmd.data)\" format=\(cmd.format) (cursor=\(modeStr))\n", stderr)
        let outPath: UnsafePointer<CChar>
        var allocatedPath: UnsafeMutablePointer<CChar>? = nil
        if !cmd.data.isEmpty {
            allocatedPath = strdup(cmd.data)
            outPath = UnsafePointer(allocatedPath!)
        } else if let path = gWindowConfig.text_dump_path {
            outPath = path
        } else {
            return
        }
        defer { allocatedPath.map { free($0) } }

        let format = cmd.format != 0 ? cmd.format : gWindowConfig.text_dump_format
        var outPtr: UnsafePointer<UInt8>?
        var outLen: Int = 0
        if ghostty_surface_text_dump(surface, format, &outPtr, &outLen) {
            if let ptr = outPtr {
                defer { ghostty_surface_free_dump(ptr, outLen) }
                let data = Data(bytes: ptr, count: outLen)
                let pathStr = String(cString: outPath)
                try? data.write(to: URL(fileURLWithPath: pathStr))
            }
        }
    case .wait:
        break // handled by executeCommands
    }
}

// ---------------------------------------------------------------------------
// AppDelegate
// ---------------------------------------------------------------------------
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // -- Set CWD to exe dir so relative paths (e.g. command = direct:./<slug>_core) resolve --
        FileManager.default.changeCurrentDirectoryPath(getExeDir())

        // -- Load manifest for window config --
        if let manifestPath = getBundledPath("trolley.toml") {
            var ghosttyLen: Int = 0
            manifestPath.withCString { ptr in
                _ = trolley_load_manifest(ptr, &gWindowConfig, &ghosttyLen)
            }
        }

        // -- Load bundled environment variables (must precede ghostty_init) --
        loadBundledEnvironment()

        // -- Inject runtime PID as environment variable if configured --
        let pid = ProcessInfo.processInfo.processIdentifier
        let pidStr = "\(pid)"
        if let varname = gWindowConfig.inject_pid_variable {
            setenv(String(cString: varname), pidStr, 1)
        }

        // -- Write PID file if configured, and register cleanup handlers --
        if let pidFilePath = gWindowConfig.pid_file {
            let path = String(cString: pidFilePath)
            try? pidStr.write(toFile: path, atomically: true, encoding: .utf8)

            // Clean up PID file on SIGTERM/SIGINT.
            for sig: Int32 in [SIGTERM, SIGINT] {
                let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
                signal(sig, SIG_IGN)
                source.setEventHandler {
                    try? FileManager.default.removeItem(atPath: path)
                    // Re-raise with default handler for correct exit status.
                    signal(sig, SIG_DFL)
                    raise(sig)
                }
                source.resume()
                // Prevent deallocation by leaking the source intentionally.
                withExtendedLifetime(source) {}
                _ = Unmanaged.passRetained(source as AnyObject)
            }
        }

        // -- Register bundled fonts --
        registerBundledFonts()

        // -- Ghostty init --
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            fputs("trolley: ghostty_init failed\n", stderr)
            exit(1)
        }

        guard let config = ghostty_config_new() else {
            fputs("trolley: ghostty_config_new failed\n", stderr)
            exit(1)
        }

        // Load bundled ghostty.conf next to the executable.
        if let path = getBundledPath("ghostty.conf") {
            path.withCString { ptr in
                ghostty_config_load_file(config, ptr)
            }
        }
        ghostty_config_finalize(config)

        // -- Create app --
        var runtimeConfig = ghostty_runtime_config_s(
            userdata: nil,
            supports_selection_clipboard: false,
            wakeup_cb: wakeupCallback,
            action_cb: actionCallback,
            read_clipboard_cb: readClipboardCallback,
            confirm_read_clipboard_cb: confirmReadClipboardCallback,
            write_clipboard_cb: writeClipboardCallback,
            close_surface_cb: closeSurfaceCallback
        )

        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            ghostty_config_free(config)
            fputs("trolley: ghostty_app_new failed\n", stderr)
            exit(1)
        }
        ghostty_config_free(config)
        gApp = app

        // -- Create window --
        let initialWidth = gWindowConfig.initial_width > 0 ? CGFloat(gWindowConfig.initial_width) : 800
        let initialHeight = gWindowConfig.initial_height > 0 ? CGFloat(gWindowConfig.initial_height) : 600

        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if gWindowConfig.resizable != 0 {  // -1 (unset) or 1 (true) → resizable
            styleMask.insert(.resizable)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "trolley"

        // Min/max size limits (each dimension independent)
        if gWindowConfig.min_width > 0 || gWindowConfig.min_height > 0 {
            window.minSize = NSSize(
                width: gWindowConfig.min_width > 0 ? CGFloat(gWindowConfig.min_width) : 0,
                height: gWindowConfig.min_height > 0 ? CGFloat(gWindowConfig.min_height) : 0
            )
        }
        if gWindowConfig.max_width > 0 || gWindowConfig.max_height > 0 {
            window.maxSize = NSSize(
                width: gWindowConfig.max_width > 0 ? CGFloat(gWindowConfig.max_width) : CGFloat.greatestFiniteMagnitude,
                height: gWindowConfig.max_height > 0 ? CGFloat(gWindowConfig.max_height) : CGFloat.greatestFiniteMagnitude
            )
        }

        window.center()
        gWindow = window

        // -- Create view and surface --
        let view = TrolleyView(frame: window.contentView!.bounds)
        view.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(view)
        window.makeFirstResponder(view)

        // Accept mouse move events
        window.acceptsMouseMovedEvents = true

        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform.macos.nsview = Unmanaged.passUnretained(view).toOpaque()
        surfaceConfig.scale_factor = window.backingScaleFactor

        guard let surface = ghostty_surface_new(app, &surfaceConfig) else {
            fputs("trolley: ghostty_surface_new failed\n", stderr)
            exit(1)
        }
        gSurface = surface

        // Set initial size
        let backed = view.convertToBacking(view.bounds.size)
        ghostty_surface_set_size(surface, UInt32(backed.width), UInt32(backed.height))
        ghostty_surface_set_content_scale(surface, Double(window.backingScaleFactor), Double(window.backingScaleFactor))
        ghostty_surface_set_focus(surface, true)

        // -- Show window (skip in headless mode) --
        let headless = CommandLine.arguments.contains("--headless")
        if !headless {
            window.makeKeyAndOrderFront(nil)
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
let delegate = AppDelegate()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.delegate = delegate

// Resolve command file path: TROLLEY_COMMAND_FILE env var overrides config.
let commandFilePath: String? = {
    if let envPath = ProcessInfo.processInfo.environment["TROLLEY_COMMAND_FILE"], !envPath.isEmpty {
        return envPath
    }
    if let configPath = gWindowConfig.command_file {
        return String(cString: configPath)
    }
    return nil
}()

// Register SIGUSR1 for command file processing.
var commandSignalSource: DispatchSourceSignal?
if let cmdPath = commandFilePath {
    signal(SIGUSR1, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    source.setEventHandler {
        loadAndExecuteCommandFile(path: cmdPath)
    }
    source.resume()
    commandSignalSource = source  // prevent deallocation
    fputs("trolley: command_file=\(cmdPath) pid=\(ProcessInfo.processInfo.processIdentifier) (send SIGUSR1 to trigger)\n", stderr)
} else {
    fputs("trolley: command_file not configured\n", stderr)
}

app.run()

// Clean up PID file on exit.
if let pidFilePath = gWindowConfig.pid_file {
    try? FileManager.default.removeItem(atPath: String(cString: pidFilePath))
}
