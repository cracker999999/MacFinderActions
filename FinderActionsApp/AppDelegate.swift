import Cocoa

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum RequestAction: String {
        case codex
    }

    static func main() {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Helper app, no UI.
        NSApp.setActivationPolicy(.accessory)
        log("didFinishLaunching")
        if handleCommandLineInvocation() {
            return
        }
        handleRequestFileInvocation()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        log("willFinishLaunching")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        log("open urls count=\(urls.count)")
        for url in urls {
            log("received url=\(url.absoluteString)")
            guard url.scheme == "finderactions" else { continue }
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            guard let path = components.queryItems?.first(where: { $0.name == "path" })?.value else { continue }
            log("parsed path=\(path)")
            handle(action: .codex, directory: path)
        }
    }

    private func requestFileURL() -> URL {
        URL(fileURLWithPath: "/private/tmp/finderactions-request.txt", isDirectory: false)
    }

    private func handleRequestFileInvocation() {
        let fileURL = requestFileURL()
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
            log("handleRequestFileInvocation: no request file")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
            return
        }

        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 else {
            log("handleRequestFileInvocation: malformed request file")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
            return
        }

        let action: RequestAction
        let path: String
        if lines.count >= 3, let parsed = RequestAction(rawValue: String(lines[1])) {
            action = parsed
            path = String(lines[2])
            log("handleRequestFileInvocation: action=\(action.rawValue) directory=\(path)")
        } else {
            // Backward-compatible fallback for old two-line request format.
            action = .codex
            path = String(lines[1])
            log("handleRequestFileInvocation: legacy format directory=\(path)")
        }

        // Consume request to avoid duplicate openings.
        try? FileManager.default.removeItem(at: fileURL)

        handle(action: action, directory: path)
    }

    private func handle(action: RequestAction, directory: String) {
        switch action {
        case .codex:
            openCodexInTerminal(directory: directory)
        }
    }

    private func openCodexInTerminal(directory: String) {
        let cmd = """
        export PATH=/usr/local/bin:$PATH; \
        cd \(shellQuote(directory)); \
        clear; \
        exec codex
        """
        let script = """
        tell application id "com.apple.Terminal"
            do script "\(appleScriptQuote(cmd))"
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            _ = appleScript.executeAndReturnError(&error)
        } else {
            error = ["message": "failed to initialize NSAppleScript"]
        }

        if let error {
            log("openCodexInTerminal: NSAppleScript error=\(error)")
        } else {
            log("openCodexInTerminal: NSAppleScript success")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    private func shellQuote(_ input: String) -> String {
        "'" + input.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func appleScriptQuote(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func log(_ message: String) {
        guard let url = logFileURL() else { return }
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let fh = try? FileHandle(forWritingTo: url) {
                defer { try? fh.close() }
                try? fh.seekToEnd()
                try? fh.write(contentsOf: data)
            }
        } else {
            try? data.write(to: url)
        }
    }

    private func logFileURL() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("FinderActions", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app.log", isDirectory: false)
    }

    private func handleCommandLineInvocation() -> Bool {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--open-codex"), args.count > idx + 1 else {
            return false
        }
        let directory = args[idx + 1]
        log("command line invocation directory=\(directory)")
        handle(action: .codex, directory: directory)
        return true
    }
}
