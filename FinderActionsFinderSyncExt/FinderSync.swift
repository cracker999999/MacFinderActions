import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    private enum MenuAction: Int, CaseIterable {
        case openInCodex

        var title: String {
            switch self {
            case .openInCodex:
                return "Open in Codex"
            }
        }

        var requestActionID: String {
            switch self {
            case .openInCodex:
                return "codex"
            }
        }
    }

    override init() {
        super.init()

        // Global monitor scope so the menu can appear in most Finder folders.
        let rootURL = URL(fileURLWithPath: "/", isDirectory: true)
        FIFinderSyncController.default().directoryURLs = [rootURL]
        log("init, directoryURLs=[/]")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        log("menu(for: \(menuKind.rawValue))")
        switch menuKind {
        case .contextualMenuForContainer:
            return makeMenu()
        case .contextualMenuForItems:
            // Some Finder views can dispatch a blank-area click as "items" with no selection.
            let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
            log("items selected count=\(selected.count)")
            return selected.isEmpty ? makeMenu() : nil
        default:
            return nil
        }
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = MenuAction(rawValue: sender.tag) else {
            log("performMenuAction: invalid tag=\(sender.tag)")
            return
        }
        perform(action: action)
    }

    private func perform(action: MenuAction) {
        guard let targetURL = FIFinderSyncController.default().targetedURL() else {
            log("perform action=\(action.requestActionID): no targetedURL")
            return
        }

        let path = targetURL.path
        log("perform action=\(action.requestActionID): targetedURL=\(path)")

        if writeLaunchRequest(actionID: action.requestActionID, path: path) {
            log("perform action=\(action.requestActionID): request written")
        } else {
            log("perform action=\(action.requestActionID): failed to write request")
        }

        launchContainingApp()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        for action in MenuAction.allCases {
            let item = NSMenuItem(
                title: action.title,
                action: #selector(performMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = action.rawValue
            menu.addItem(item)
        }
        return menu
    }

    private func containingAppURL() -> URL? {
        // .../FinderActions.app/Contents/PlugIns/FinderActionsFinderSyncExt.appex
        let appexURL = Bundle.main.bundleURL
        let appURL = appexURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // FinderActions.app

        guard appURL.pathExtension == "app" else {
            log("containingAppURL: unexpected path \(appURL.path)")
            return nil
        }
        return appURL
    }

    private func requestFileURL() -> URL {
        URL(fileURLWithPath: "/private/tmp/finderactions-request.txt", isDirectory: false)
    }

    private func writeLaunchRequest(actionID: String, path: String) -> Bool {
        let payload = "\(Date().timeIntervalSince1970)\n\(actionID)\n\(path)\n"
        let fileURL = requestFileURL()
        do {
            try payload.write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
            return true
        } catch {
            log("writeLaunchRequest error: \(error.localizedDescription)")
            return false
        }
    }

    private func launchContainingApp() {
        guard let appURL = containingAppURL() else {
            log("launchContainingApp: containing app not found")
            return
        }

        let process = Process()
        let err = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", "-a", appURL.path]
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            log("launchContainingApp open exit=\(process.terminationStatus) stderr=\(stderr)")
        } catch {
            log("launchContainingApp open error: \(error.localizedDescription)")
        }
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
        return dir.appendingPathComponent("findersync.log", isDirectory: false)
    }
}
