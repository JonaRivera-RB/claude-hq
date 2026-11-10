import Foundation

/// Conecta Claude HQ con Claude Code: agrega hooks silenciosos y envuelve la status line
/// existente (la conserva y le agrega el segmento de límites).
enum Installer {
    static let events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                         "PostToolUseFailure", "Notification", "PermissionRequest", "Stop", "StopFailure",
                         "SubagentStart", "SubagentStop"]
    static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest"]
    static let marker = "ClaudeHQ"

    static var binPath: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }
    static func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

    static func readSettings() -> [String: Any] {
        guard let d = FileManager.default.contents(atPath: HQPaths.claudeSettings),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }

    static func writeSettings(_ s: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        hqWriteAtomic(data, to: HQPaths.claudeSettings)
    }

    static func backup() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: HQPaths.claudeSettings) else { return }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let dest = HQPaths.hqDir + "/settings.backup-\(f.string(from: Date())).json"
        HQPaths.ensureDirs()
        try? fm.copyItem(atPath: HQPaths.claudeSettings, toPath: dest)
    }

    static var hookCommand: String { quoted(binPath) + " hook 2>/dev/null || true" }
    static var statusCommand: String { quoted(binPath) + " statusline 2>/dev/null" }

    /// Conectado pero con comandos de una versión anterior (o con otra ruta de la app).
    static func needsUpdate() -> Bool {
        guard isInstalled() else { return false }
        let s = readSettings()
        let cmd = ((s["statusLine"] as? [String: Any])?["command"] as? String) ?? ""
        let hooks = s["hooks"] as? [String: Any] ?? [:]
        let pre = (hooks["PreToolUse"] as? [[String: Any]] ?? []).first { entryIsOurs($0) }
        let hcmd = ((pre?["hooks"] as? [[String: Any]])?.first { (($0["command"] as? String) ?? "").contains(marker) }?["command"] as? String) ?? ""
        return cmd != statusCommand || hcmd != hookCommand
    }

    static func isInstalled() -> Bool {
        let s = readSettings()
        let cmd = ((s["statusLine"] as? [String: Any])?["command"] as? String) ?? ""
        let hooks = s["hooks"] as? [String: Any] ?? [:]
        let hasHooks = (hooks["PreToolUse"] as? [[String: Any]] ?? []).contains { entryIsOurs($0) }
        return cmd.contains(marker) && hasHooks
    }

    static func entryIsOurs(_ entry: [String: Any]) -> Bool {
        let hs = entry["hooks"] as? [[String: Any]] ?? []
        return hs.contains { (($0["command"] as? String) ?? "").contains(marker) }
    }

    static func install() throws {
        backup()
        var s = readSettings()
        var hooks = s["hooks"] as? [String: Any] ?? [:]
        let command = hookCommand
        for ev in events {
            var list = (hooks[ev] as? [[String: Any]] ?? []).filter { !entryIsOurs($0) }
            var entry: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]]]
            if toolEvents.contains(ev) { entry["matcher"] = "*" }
            list.append(entry)
            hooks[ev] = list
        }
        s["hooks"] = hooks

        var cfg = HQConfig.load()
        let current = s["statusLine"] as? [String: Any]
        let currentCmd = current?["command"] as? String
        if let c = currentCmd, !c.contains(marker) { cfg.prevStatusLine = c }
        var sl = current ?? [:]
        sl["type"] = "command"
        sl["command"] = statusCommand
        s["statusLine"] = sl
        cfg.installed = true
        cfg.save()
        try writeSettings(s)
    }

    static func uninstall() throws {
        backup()
        var s = readSettings()
        var hooks = s["hooks"] as? [String: Any] ?? [:]
        for (ev, v) in hooks {
            let list = (v as? [[String: Any]] ?? []).filter { !entryIsOurs($0) }
            hooks[ev] = list.isEmpty ? nil : list
        }
        s["hooks"] = hooks
        var cfg = HQConfig.load()
        if var sl = s["statusLine"] as? [String: Any], ((sl["command"] as? String) ?? "").contains(marker) {
            if let prev = cfg.prevStatusLine, !prev.isEmpty {
                sl["command"] = prev
                s["statusLine"] = sl
            } else {
                s["statusLine"] = nil
            }
        }
        cfg.installed = false
        cfg.save()
        try writeSettings(s)
    }
}
