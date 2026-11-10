import Foundation
import Security

// MARK: - Login con Claude (usa el mismo login de Claude Code: `claude auth`)

struct ClaudeAccount {
    var loggedIn: Bool
    var email: String?
    var org: String?
    var plan: String?
    var method: String?
}

enum ClaudeCLI {
    static var path: String? = {
        let home = HQPaths.realHome
        let candidates = [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", home + "/.claude/local/claude"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        // Último recurso: preguntarle al shell de login.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }()

    static func run(_ args: [String], timeout: TimeInterval = 15) -> Data? {
        guard let bin = path else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:" + HQPaths.realHome + "/.local/bin"
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        var data = Data()
        let g = DispatchGroup(); g.enter()
        DispatchQueue.global().async { data = pipe.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        if g.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return nil }
        p.waitUntilExit()
        return data
    }

    static func account() -> ClaudeAccount? {
        guard let d = run(["auth", "status", "--json"]),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let plan = (o["subscriptionType"] as? String).map { s -> String in
            switch s.lowercased() {
            case "pro": return "Pro"
            case "max": return "Max"
            case "team": return "Team"
            case "enterprise": return "Enterprise"
            default: return s.capitalized
            }
        }
        return ClaudeAccount(loggedIn: (o["loggedIn"] as? Bool) ?? false,
                             email: o["email"] as? String,
                             org: o["orgName"] as? String,
                             plan: plan,
                             method: o["authMethod"] as? String)
    }

    static var loginCommand: String { TerminalFocus.shellQuote(path ?? "claude") + " auth login" }
    static func logout() { _ = run(["auth", "logout"]) }
}

// MARK: - Llavero (solo para la Admin API key opcional)

enum Keychain {
    static let service = "com.jonarivera.ClaudeHQ.admin-key"

    static func save(_ value: String) -> Bool {
        delete()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: "anthropic-admin",
                                kSecValueData as String: Data(value.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: "anthropic-admin",
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func delete() -> Bool {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: "anthropic-admin"]
        return SecItemDelete(q as CFDictionary) == errSecSuccess
    }
}

// MARK: - Admin API de Anthropic (gasto y tokens de la API; solo lectura)

struct APIUsage {
    var monthUSD: Double?
    var todayTokens: Int = 0
    var monthTokens: Int = 0
    var byModel: [(String, Int)] = []
    var error: String?
    var updatedAt: Double = Date().timeIntervalSince1970
}

enum AdminAPI {
    static let base = "https://api.anthropic.com/v1/organizations"

    static func fetch(key: String) async -> APIUsage {
        var result = APIUsage()
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let comps = utc.dateComponents([.year, .month], from: now)
        let monthStart = utc.date(from: comps)!
        let todayStart = utc.startOfDay(for: now)
        let f = ISO8601DateFormatter()
        let startStr = f.string(from: monthStart)

        // Tokens por modelo
        var modelTotals: [String: Int] = [:]
        var page: String?
        repeat {
            var q = "starting_at=\(startStr)&bucket_width=1d&limit=31&group_by[]=model"
            if let p = page { q += "&page=\(p)" }
            guard let obj = await get("\(base)/usage_report/messages?\(q)", key: key, error: &result.error) else { break }
            for bucket in obj["data"] as? [[String: Any]] ?? [] {
                let bStart = (bucket["starting_at"] as? String).flatMap { f.date(from: $0) } ?? .distantPast
                for r in bucket["results"] as? [[String: Any]] ?? [] {
                    func n(_ k: String) -> Int { (r[k] as? NSNumber)?.intValue ?? 0 }
                    let cc = r["cache_creation"] as? [String: Any] ?? [:]
                    let ccTok = ((cc["ephemeral_5m_input_tokens"] as? NSNumber)?.intValue ?? 0) + ((cc["ephemeral_1h_input_tokens"] as? NSNumber)?.intValue ?? 0)
                    let tot = n("uncached_input_tokens") + n("output_tokens") + ccTok
                    result.monthTokens += tot
                    if bStart >= todayStart { result.todayTokens += tot }
                    let m = (r["model"] as? String) ?? "otro"
                    modelTotals[TranscriptScanner.family(m), default: 0] += tot
                }
            }
            page = (obj["has_more"] as? Bool) == true ? obj["next_page"] as? String : nil
        } while page != nil
        result.byModel = modelTotals.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }

        // Gasto en USD (los montos vienen en centavos)
        var cents = 0.0
        var gotCost = false
        page = nil
        repeat {
            var q = "starting_at=\(startStr)&bucket_width=1d&limit=31"
            if let p = page { q += "&page=\(p)" }
            var err: String?
            guard let obj = await get("\(base)/cost_report?\(q)", key: key, error: &err) else { if result.error == nil { result.error = err }; break }
            gotCost = true
            for bucket in obj["data"] as? [[String: Any]] ?? [] {
                for r in bucket["results"] as? [[String: Any]] ?? [] {
                    if let s = r["amount"] as? String, let v = Double(s) { cents += v }
                    else if let v = (r["amount"] as? NSNumber)?.doubleValue { cents += v }
                }
            }
            page = (obj["has_more"] as? Bool) == true ? obj["next_page"] as? String : nil
        } while page != nil
        if gotCost { result.monthUSD = cents / 100 }
        return result
    }

    static func get(_ url: String, key: String, error: inout String?) async -> [String: Any]? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("ClaudeHQ/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if code != 200 {
                let msg = ((obj?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(code)"
                error = code == 401 || code == 403 ? "La key no es válida o no es de administrador" : msg
                return nil
            }
            return obj
        } catch {
            return nil
        }
    }
}

// MARK: - Ajustes de Claude Code (modelo y modo de permisos por defecto)

enum ClaudeSettings {
    static func current() -> (model: String, perm: String) {
        let s = Installer.readSettings()
        let model = (s["model"] as? String) ?? ""
        let perm = ((s["permissions"] as? [String: Any])?["defaultMode"] as? String) ?? "default"
        return (model, perm)
    }

    static func setModel(_ family: String) throws {
        var s = Installer.readSettings()
        let cur = (s["model"] as? String) ?? ""
        let keep1m = cur.contains("[1m]") && family != "haiku"
        s["model"] = family + (keep1m ? "[1m]" : "")
        try Installer.writeSettings(s)
    }

    static func setPermissionMode(_ mode: String) throws {
        var s = Installer.readSettings()
        var p = s["permissions"] as? [String: Any] ?? [:]
        if mode == "default" { p.removeValue(forKey: "defaultMode") } else { p["defaultMode"] = mode }
        s["permissions"] = p
        try Installer.writeSettings(s)
    }
}
