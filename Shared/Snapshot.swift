import Foundation

/// Rutas compartidas. Usa el home real (también dentro del sandbox del widget).
enum HQPaths {
    static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }
    static var hqDir: String { realHome + "/.claude-hq" }
    static var hookStateDir: String { hqDir + "/sessions" }
    static var statusDir: String { hqDir + "/status" }
    static var limitsFile: String { hqDir + "/limits.json" }
    static var snapshotFile: String { hqDir + "/snapshot.json" }
    static var configFile: String { hqDir + "/config.json" }
    static var claudeDir: String { realHome + "/.claude" }
    static var claudeSessionsDir: String { claudeDir + "/sessions" }
    static var claudeProjectsDir: String { claudeDir + "/projects" }
    static var claudeSettings: String { claudeDir + "/settings.json" }

    static func ensureDirs() {
        for d in [hqDir, hookStateDir, statusDir] {
            try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        }
    }
}

/// Resumen que la app escribe para el widget y la status line.
struct HQSnapshot: Codable {
    struct Window: Codable {
        var usedPercentage: Double
        var resetsAt: Double
    }
    struct Agent: Codable {
        var id: String
        var name: String
        var model: String
        var state: String   // working | waiting | idle | error
        var now: String
        var subagents: Int
    }
    var updatedAt: Double
    var fiveHour: Window?
    var sevenDay: Window?
    var limitsUpdatedAt: Double?
    var tokensToday: Int
    var agents: [Agent]
    var account: String?
    var plan: String?

    static func load() -> HQSnapshot? {
        guard let data = FileManager.default.contents(atPath: HQPaths.snapshotFile) else { return nil }
        return try? JSONDecoder().decode(HQSnapshot.self, from: data)
    }
}

enum HQFormat {
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000 { return String(format: "%.2fM", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.0fk", d / 1_000) }
        return "\(n)"
    }
    static func clock(_ epoch: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        let date = Date(timeIntervalSince1970: epoch)
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: date)
    }
}

/// Escritura atómica: nunca deja un JSON a medias.
func hqWriteAtomic(_ data: Data, to path: String) {
    let tmp = path + ".tmp-\(getpid())"
    if FileManager.default.createFile(atPath: tmp, contents: data) {
        _ = rename(tmp, path)
    }
}

/// Igual que hqWriteAtomic, pero lanza error si no pudo escribir (para archivos del usuario).
func hqWriteAtomicThrowing(_ data: Data, to path: String) throws {
    let tmp = path + ".tmp-\(getpid())"
    try data.write(to: URL(fileURLWithPath: tmp))
    if rename(tmp, path) != 0 {
        let err = errno
        try? FileManager.default.removeItem(atPath: tmp)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(err),
                      userInfo: [NSLocalizedDescriptionKey: "No pude escribir \(path): \(String(cString: strerror(err)))"])
    }
}
