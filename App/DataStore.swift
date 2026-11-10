import Foundation

/// Junta todas las fuentes locales en un solo estado para la interfaz.
/// Fuentes: ~/.claude/sessions (sesiones vivas), hooks y status line de Claude HQ,
/// transcripts (tokens) y `claude auth status` (cuenta). Nada de esto gasta tokens.
final class DataStore {
    struct LogVM: Encodable { var t: Double; var x: String; var who: String?; var family: String? }
    struct AgentVM: Encodable {
        var id: String
        var pid: Int32
        var name: String
        var model: String
        var family: String
        var state: String
        var now: String
        var nowAt: Double?
        var subs: [String]
        var log: [LogVM]
        var history: [LogVM]
        var startedAt: Double?
        var ctx: Int?
        var tokens: Int
        var app: String?
        var cwd: String
        var tracked: Bool
    }
    struct WindowVM: Encodable { var used: Double; var resetsAt: Double; var expired: Bool }
    struct Payload: Encodable {
        var now: Double
        var agents: [AgentVM]
        var fiveHour: WindowVM?
        var sevenDay: WindowVM?
        var limitsUpdatedAt: Double?
        var tokensToday: [String: Int]
        var byModelToday: [[String: String]]
        var account: [String: String]?
        var loggedIn: Bool?
        var installed: Bool
        var needsUpdate: Bool
        var settingsModel: String
        var settingsPerm: String
        var api: [String: String]?
        var apiConfigured: Bool
        var alertsEnabled: Bool
        var soundEnabled: Bool
        var ticker: [LogVM]
    }

    private let scanner = TranscriptScanner()
    private var account: ClaudeAccount?
    private var accountCheckedAt: Double = 0
    private var hostCache: [Int32: HostApp] = [:]
    var api: APIUsage?
    var apiConfigured = Keychain.load() != nil
    private(set) var hosts: [String: (HostApp?, String?, String)] = [:] // sid -> (host, tty, cwd)

    func forceAccountRefresh() { accountCheckedAt = 0 }

    func refresh() -> Payload {
        let now = Date().timeIntervalSince1970
        scanner.scan()
        if now - accountCheckedAt > 60 {
            accountCheckedAt = now
            if let a = ClaudeCLI.account() { account = a }
        }
        let table = TerminalFocus.processTable()
        let settings = ClaudeSettings.current()

        var agents: [AgentVM] = []
        var newHosts: [String: (HostApp?, String?, String)] = [:]
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: HQPaths.claudeSessionsDir)) ?? []
        var nameCount: [String: Int] = [:]
        struct Raw { var o: [String: Any]; var pid: Int32; var sid: String; var cwd: String }
        var raws: [Raw] = []
        for f in files where f.hasSuffix(".json") {
            guard let d = fm.contents(atPath: HQPaths.claudeSessionsDir + "/" + f),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let pid = (o["pid"] as? NSNumber)?.int32Value,
                  let sid = o["sessionId"] as? String else { continue }
            guard kill(pid, 0) == 0 || errno == EPERM else { continue }
            let cwd = (o["cwd"] as? String) ?? ""
            raws.append(Raw(o: o, pid: pid, sid: sid, cwd: cwd))
            nameCount[URL(fileURLWithPath: cwd).lastPathComponent, default: 0] += 1
        }
        raws.sort { (($0.o["startedAt"] as? NSNumber)?.doubleValue ?? 0) < (($1.o["startedAt"] as? NSNumber)?.doubleValue ?? 0) }

        for r in raws {
            let o = r.o
            let safe = r.sid.replacingOccurrences(of: "/", with: "_")
            let hook = fm.contents(atPath: HQPaths.hookStateDir + "/\(safe).json").flatMap { try? JSONDecoder().decode(HookState.self, from: $0) }
            let status = fm.contents(atPath: HQPaths.statusDir + "/\(safe).json").flatMap { try? JSONDecoder().decode(SessionStatus.self, from: $0) }

            // Nombre legible
            var name = URL(fileURLWithPath: r.cwd).lastPathComponent
            if (o["nameSource"] as? String) != "derived", let n = o["name"] as? String, !n.isEmpty { name = n }
            else if nameCount[name, default: 0] > 1, let n = o["name"] as? String { name = n }
            if name.isEmpty { name = "sesión" }

            // Estado
            let fileStatus = (o["status"] as? String) ?? "idle"
            var state: String
            switch fileStatus {
            case "busy": state = "working"
            case "waiting", "blocked": state = "waiting"
            default: state = "idle"
            }
            if let h = hook {
                if h.status == "waiting" && state != "idle" { state = "waiting" }
                if h.status == "error" && state == "idle" { state = "error" }
            }

            var nowText: String
            switch state {
            case "waiting": nowText = (hook?.status == "waiting" ? hook?.now : nil) ?? "Necesita tu permiso para continuar"
            case "working": nowText = (hook?.status == "working" ? hook?.now : nil) ?? "Trabajando…"
            case "error": nowText = hook?.now ?? "Se detuvo por un error"
            default: nowText = (hook?.status == "idle" ? hook?.now : nil) ?? "Esperando tu siguiente mensaje"
            }

            // Modelo y contexto
            var modelName = status?.model ?? scanner.last[r.sid]?.model.map { TranscriptScanner.displayName($0) } ?? "Claude"
            if let p = modelName.range(of: " (") { modelName = String(modelName[..<p.lowerBound]) }
            let family = TranscriptScanner.family(status?.modelId ?? status?.model ?? scanner.last[r.sid]?.model ?? modelName)
            var ctx: Int? = status?.ctxUsed.map { Int($0.rounded()) }
            if ctx == nil, let l = scanner.last[r.sid], l.contextTokens > 0 {
                let window = (settings.model.contains("[1m]") || l.contextTokens > 200_000) ? 1_000_000.0 : 200_000.0
                ctx = Int((Double(l.contextTokens) / window * 100).rounded())
            }

            // Terminal
            let host: HostApp?
            if let cached = hostCache[r.pid] { host = cached } else {
                host = TerminalFocus.host(for: r.pid, table: table)
                if let h = host { hostCache[r.pid] = h }
            }
            let tty = TerminalFocus.tty(for: r.pid, table: table)
            newHosts[r.sid] = (host, tty, r.cwd)

            let subs = (hook?.subOrder ?? []).compactMap { hook?.subs[$0] }
            let allLogs = (hook?.log ?? []).map { LogVM(t: $0.t, x: $0.x, who: nil, family: nil) }
            let logs = allLogs.prefix(6)
            let started = (o["startedAt"] as? NSNumber).map { $0.doubleValue / 1000 }
            agents.append(AgentVM(id: r.sid, pid: r.pid, name: name, model: modelName, family: family, state: state,
                                  now: nowText, nowAt: hook?.nowAt, subs: subs, log: Array(logs), history: allLogs, startedAt: started, ctx: ctx,
                                  tokens: scanner.perSession[r.sid]?.headline ?? 0,
                                  app: host?.name, cwd: r.cwd, tracked: hook != nil))
        }
        hosts = newHosts
        hostCache = hostCache.filter { pid, _ in raws.contains { $0.pid == pid } }

        // Límites del plan (dato oficial de la status line)
        let lf = StatuslineHandler.loadLimits()
        func wvm(_ w: HQSnapshot.Window?) -> WindowVM? {
            guard let w = w else { return nil }
            let expired = w.resetsAt <= now
            return WindowVM(used: expired ? 0 : w.usedPercentage, resetsAt: w.resetsAt, expired: expired)
        }

        let t = scanner.today
        let byModel = scanner.perModel.sorted { $0.value.headline > $1.value.headline }
            .map { ["family": $0.key, "tokens": "\($0.value.headline)"] }

        var ticker: [LogVM] = []
        for a in agents { for l in a.log.prefix(3) { ticker.append(LogVM(t: l.t, x: l.x, who: a.name, family: a.family)) } }
        ticker.sort { $0.t > $1.t }

        var apiDict: [String: String]?
        if let a = api {
            apiDict = ["monthUSD": a.monthUSD.map { String(format: "%.2f", $0) } ?? "",
                       "todayTokens": "\(a.todayTokens)", "monthTokens": "\(a.monthTokens)",
                       "byModel": a.byModel.map { "\($0.0):\($0.1)" }.joined(separator: ","),
                       "error": a.error ?? "", "updatedAt": "\(a.updatedAt)"]
        }

        let cfg = HQConfig.load()
        return Payload(
            now: now, agents: agents,
            fiveHour: wvm(lf?.fiveHour), sevenDay: wvm(lf?.sevenDay), limitsUpdatedAt: lf?.updatedAt,
            tokensToday: ["headline": t.headline, "input": t.input, "output": t.output, "cacheWrite": t.cacheWrite, "cacheRead": t.cacheRead],
            byModelToday: byModel,
            account: account.map { ["email": $0.email ?? "", "org": $0.org ?? "", "plan": $0.plan ?? "", "method": $0.method ?? ""] },
            loggedIn: account?.loggedIn,
            installed: Installer.isInstalled(),
            needsUpdate: Installer.needsUpdate(),
            settingsModel: TranscriptScanner.family(settings.model.isEmpty ? "opus" : settings.model),
            settingsPerm: settings.perm,
            api: apiDict, apiConfigured: apiConfigured,
            alertsEnabled: cfg.alertsEnabled,
            soundEnabled: cfg.soundEnabled,
            ticker: Array(ticker.prefix(12)))
    }

    func snapshot(from p: Payload) -> HQSnapshot {
        HQSnapshot(updatedAt: p.now,
                   fiveHour: p.fiveHour.map { .init(usedPercentage: $0.used, resetsAt: $0.resetsAt) },
                   sevenDay: p.sevenDay.map { .init(usedPercentage: $0.used, resetsAt: $0.resetsAt) },
                   limitsUpdatedAt: p.limitsUpdatedAt,
                   tokensToday: p.tokensToday["headline"] ?? 0,
                   agents: p.agents.map { .init(id: $0.id, name: $0.name, model: $0.family, state: $0.state, now: $0.now, subagents: $0.subs.count) },
                   account: p.account?["email"], plan: p.account?["plan"])
    }
}
