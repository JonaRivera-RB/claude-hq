import Foundation

struct HQConfig: Codable {
    var prevStatusLine: String?
    var installed: Bool = false
    var alertsEnabled: Bool = true
    var soundEnabled: Bool = true
    var showInStatusLine: Bool = true
    var newSessionApp: String = "auto"

    init() {}
    /// Tolerante a versiones anteriores: un campo nuevo nunca debe hacer perder `prevStatusLine`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prevStatusLine = try c.decodeIfPresent(String.self, forKey: .prevStatusLine)
        installed = try c.decodeIfPresent(Bool.self, forKey: .installed) ?? false
        alertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? true
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        showInStatusLine = try c.decodeIfPresent(Bool.self, forKey: .showInStatusLine) ?? true
        newSessionApp = try c.decodeIfPresent(String.self, forKey: .newSessionApp) ?? "auto"
    }

    static func load() -> HQConfig {
        guard let d = FileManager.default.contents(atPath: HQPaths.configFile),
              let c = try? JSONDecoder().decode(HQConfig.self, from: d) else { return HQConfig() }
        return c
    }
    func save() {
        HQPaths.ensureDirs()
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(self) { hqWriteAtomic(d, to: HQPaths.configFile) }
    }
}

/// Datos por sesión que vienen de la status line (oficial de Claude Code).
struct SessionStatus: Codable {
    var model: String?
    var modelId: String?
    var ctxUsed: Double?
    var ctxSize: Double?
    var cwd: String?
    var updatedAt: Double
}

struct LimitsFile: Codable {
    var fiveHour: HQSnapshot.Window?
    var sevenDay: HQSnapshot.Window?
    var updatedAt: Double
}

enum StatuslineHandler {
    static func run() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        HQPaths.ensureDirs()
        let now = Date().timeIntervalSince1970
        var limits: LimitsFile?
        if let obj = try? JSONSerialization.jsonObject(with: input) as? [String: Any] {
            if let sid = obj["session_id"] as? String, !sid.isEmpty {
                let model = obj["model"] as? [String: Any]
                let ctx = obj["context_window"] as? [String: Any]
                let st = SessionStatus(
                    model: model?["display_name"] as? String,
                    modelId: model?["id"] as? String,
                    ctxUsed: (ctx?["used_percentage"] as? NSNumber)?.doubleValue,
                    ctxSize: (ctx?["context_window_size"] as? NSNumber)?.doubleValue,
                    cwd: obj["cwd"] as? String,
                    updatedAt: now)
                if let d = try? JSONEncoder().encode(st) {
                    hqWriteAtomic(d, to: HQPaths.statusDir + "/\(sid.replacingOccurrences(of: "/", with: "_")).json")
                }
            }
            if let rl = obj["rate_limits"] as? [String: Any] {
                var lf = (FileManager.default.contents(atPath: HQPaths.limitsFile).flatMap { try? JSONDecoder().decode(LimitsFile.self, from: $0) }) ?? LimitsFile(updatedAt: now)
                func win(_ k: String) -> HQSnapshot.Window? {
                    guard let w = rl[k] as? [String: Any],
                          let u = (w["used_percentage"] as? NSNumber)?.doubleValue,
                          let r = (w["resets_at"] as? NSNumber)?.doubleValue else { return nil }
                    return .init(usedPercentage: u, resetsAt: r)
                }
                if let w = win("five_hour") { lf.fiveHour = w }
                if let w = win("seven_day") { lf.sevenDay = w }
                lf.updatedAt = now
                if let d = try? JSONEncoder().encode(lf) { hqWriteAtomic(d, to: HQPaths.limitsFile) }
                limits = lf
            }
        }

        let cfg = HQConfig.load()
        var out = ""
        if let prev = cfg.prevStatusLine, !prev.isEmpty {
            out = runPrevious(prev, input: input)
        }
        while out.hasSuffix("\n") { out.removeLast() }
        if cfg.showInStatusLine, let seg = segment(limits ?? loadLimits()) {
            out = out.isEmpty ? seg : out + " \u{1B}[2m│\u{1B}[0m " + seg
        }
        FileHandle.standardOutput.write((out + "\n").data(using: .utf8)!)
    }

    static func loadLimits() -> LimitsFile? {
        FileManager.default.contents(atPath: HQPaths.limitsFile).flatMap { try? JSONDecoder().decode(LimitsFile.self, from: $0) }
    }

    static func segment(_ l: LimitsFile?) -> String? {
        guard let l = l else { return nil }
        let now = Date().timeIntervalSince1970
        func part(_ label: String, _ w: HQSnapshot.Window?) -> String? {
            guard let w = w, w.resetsAt > now else { return nil }
            let p = Int(w.usedPercentage.rounded())
            let color = p >= 95 ? "\u{1B}[31m" : (p >= 80 ? "\u{1B}[33m" : "\u{1B}[2m")
            return "\(color)\(label) \(p)%\u{1B}[0m"
        }
        let parts = [part("5h", l.fiveHour), part("sem", l.sevenDay)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Ejecuta la status line que el usuario ya tenía (por ejemplo la de GSD) y devuelve su salida.
    static func runPrevious(_ cmd: String, input: Data) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        inPipe.fileHandleForWriting.write(input)
        try? inPipe.fileHandleForWriting.close()
        var data = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            data = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + 4) == .timedOut { p.terminate() }
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
