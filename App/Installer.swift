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

    enum SettingsError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let path): return "No pude leer \(path) (¿JSON inválido?). No lo toqué; corrígelo y vuelve a intentar."
            }
        }
    }

    /// Lectura tolerante, solo para consultar (nunca se usa para reescribir el archivo).
    static func readSettings() -> [String: Any] {
        (try? readSettingsForWrite()) ?? [:]
    }

    /// Lectura estricta antes de escribir: si el archivo existe pero no se puede interpretar,
    /// falla en lugar de devolver vacío, para no borrar la configuración del usuario.
    static func readSettingsForWrite() throws -> [String: Any] {
        let path = HQPaths.claudeSettings
        guard FileManager.default.fileExists(atPath: path) else { return [:] }
        guard let d = FileManager.default.contents(atPath: path) else { throw SettingsError.unreadable(path) }
        if String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw SettingsError.unreadable(path) }
        return o
    }

    /// Respalda y escribe settings.json. Respeta symlinks (escribe en el destino real),
    /// conserva los permisos del original y propaga cualquier error.
    static func writeSettings(_ s: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let fm = FileManager.default
        try fm.createDirectory(atPath: HQPaths.claudeDir, withIntermediateDirectories: true)
        try backup()
        let target = URL(fileURLWithPath: HQPaths.claudeSettings).resolvingSymlinksInPath().path
        let perms = (try? fm.attributesOfItem(atPath: target))?[.posixPermissions]
        try hqWriteAtomicThrowing(data, to: target)
        if let perms { try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: target) }
    }

    static func backup() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: HQPaths.claudeSettings) else { return }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let dest = HQPaths.hqDir + "/settings.backup-\(f.string(from: Date())).json"
        HQPaths.ensureDirs()
        if fm.fileExists(atPath: dest) { return }  // ya hay respaldo de este mismo segundo
        try fm.copyItem(atPath: URL(fileURLWithPath: HQPaths.claudeSettings).resolvingSymlinksInPath().path, toPath: dest)
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
        var s = try readSettingsForWrite()
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
        if let c = currentCmd, !c.isEmpty {
            if !c.contains(marker) { cfg.prevStatusLine = c }
        } else {
            cfg.prevStatusLine = nil
        }
        var sl = current ?? [:]
        sl["type"] = "command"
        sl["command"] = statusCommand
        s["statusLine"] = sl
        try writeSettings(s)
        cfg.installed = true
        cfg.save()
    }

    static func uninstall() throws {
        var s = try readSettingsForWrite()
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
        try writeSettings(s)
        cfg.installed = false
        cfg.save()
    }
}
