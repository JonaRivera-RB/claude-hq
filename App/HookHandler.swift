import Foundation

/// Estado que escriben los hooks de Claude Code, uno por sesión.
/// El hook nunca imprime nada: así no agrega tokens al contexto de Claude.
struct HookState: Codable {
    struct LogItem: Codable { var t: Double; var x: String }
    var sessionId: String
    var cwd: String?
    var transcriptPath: String?
    var status: String = "idle"          // working | waiting | idle | error
    var now: String = "Sesión iniciada"
    var nowAt: Double = Date().timeIntervalSince1970
    var subs: [String: String] = [:]     // agent_id -> descripción
    var subOrder: [String] = []
    var pendingSubs: [String] = []
    var log: [LogItem] = []
    var termProgram: String?
    var bundleId: String?
    var permissionMode: String?
    var updatedAt: Double = Date().timeIntervalSince1970
}

enum HookHandler {
    static func run() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let obj = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let sid = obj["session_id"] as? String, !sid.isEmpty,
              let event = obj["hook_event_name"] as? String else { return }
        HQPaths.ensureDirs()
        let safe = sid.replacingOccurrences(of: "/", with: "_")
        let path = HQPaths.hookStateDir + "/\(safe).json"

        // Bloqueo por sesión: los hooks de herramientas pueden correr en paralelo.
        let lockFd = open(path + ".lock", O_CREAT | O_RDWR, 0o644)
        if lockFd >= 0 { flock(lockFd, LOCK_EX) }
        defer { if lockFd >= 0 { flock(lockFd, LOCK_UN); close(lockFd) } }

        if event == "SessionEnd" {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: HQPaths.statusDir + "/\(safe).json")
            unlink(path + ".lock")
            return
        }

        var st: HookState
        if let d = FileManager.default.contents(atPath: path), let s = try? JSONDecoder().decode(HookState.self, from: d) {
            st = s
        } else {
            st = HookState(sessionId: sid)
        }
        st.cwd = obj["cwd"] as? String ?? st.cwd
        st.transcriptPath = obj["transcript_path"] as? String ?? st.transcriptPath
        st.permissionMode = obj["permission_mode"] as? String ?? st.permissionMode
        let env = ProcessInfo.processInfo.environment
        if let tp = env["TERM_PROGRAM"] { st.termProgram = tp }
        if let b = env["__CFBundleIdentifier"] { st.bundleId = b }

        let tool = obj["tool_name"] as? String ?? ""
        let toolInput = obj["tool_input"] as? [String: Any] ?? [:]

        switch event {
        case "SessionStart":
            st.status = "idle"
            st.subs = [:]; st.subOrder = []; st.pendingSubs = []
            setNow(&st, "Lista para tu primer mensaje")
            addLog(&st, (obj["source"] as? String) == "resume" ? "Retomó la sesión" : "Inició la sesión")
        case "UserPromptSubmit":
            st.status = "working"
            setNow(&st, "Pensando en tu mensaje…")
            addLog(&st, "Recibió un mensaje nuevo")
        case "PreToolUse":
            st.status = "working"
            setNow(&st, describe(tool, toolInput, past: false))
            if tool == "Agent" || tool == "Task" {
                let d = (toolInput["description"] as? String) ?? (toolInput["subagent_type"] as? String) ?? "Subagente"
                st.pendingSubs.append(d)
                if st.pendingSubs.count > 20 { st.pendingSubs.removeFirst() }
            }
        case "PostToolUse":
            if st.status == "waiting" { st.status = "working" }
            addLog(&st, describe(tool, toolInput, past: true))
        case "PostToolUseFailure":
            addLog(&st, "Falló: " + describe(tool, toolInput, past: false))
        case "PermissionRequest":
            st.status = "waiting"
            setNow(&st, "Pide permiso: " + describe(tool, toolInput, past: false))
            addLog(&st, "Pidió permiso")
        case "Notification":
            let type = obj["notification_type"] as? String ?? ""
            let msg = obj["message"] as? String ?? ""
            if type == "permission_prompt" || msg.lowercased().contains("permission") {
                st.status = "waiting"
                if !st.now.hasPrefix("Pide permiso") { setNow(&st, "Necesita tu permiso para continuar") }
            } else if type == "idle_prompt" {
                st.status = "idle"
                setNow(&st, "Esperando tu siguiente mensaje")
            }
        case "Stop":
            st.status = "idle"
            setNow(&st, "Terminó · lista para tu siguiente mensaje")
            addLog(&st, "Terminó la respuesta")
        case "StopFailure":
            st.status = "error"
            let err = (obj["error"] as? String) ?? (obj["error_type"] as? String) ?? "error de la API"
            setNow(&st, "Se detuvo por un error: " + String(err.prefix(80)))
            addLog(&st, "Error: " + String(err.prefix(60)))
        case "SubagentStart":
            let aid = obj["agent_id"] as? String ?? UUID().uuidString
            let d = st.pendingSubs.isEmpty ? ((obj["agent_type"] as? String) ?? "Subagente") : st.pendingSubs.removeFirst()
            st.subs[aid] = d
            st.subOrder.append(aid)
            addLog(&st, "Lanzó subagente: " + d)
        case "SubagentStop":
            if let aid = obj["agent_id"] as? String, st.subs[aid] != nil {
                st.subs.removeValue(forKey: aid)
                st.subOrder.removeAll { $0 == aid }
            } else if let first = st.subOrder.first {
                st.subs.removeValue(forKey: first)
                st.subOrder.removeFirst()
            }
        default:
            break
        }
        st.updatedAt = Date().timeIntervalSince1970
        if let data = try? JSONEncoder().encode(st) { hqWriteAtomic(data, to: path) }
    }

    private static func setNow(_ st: inout HookState, _ text: String) {
        st.now = text
        st.nowAt = Date().timeIntervalSince1970
    }

    private static func addLog(_ st: inout HookState, _ text: String) {
        st.log.insert(.init(t: Date().timeIntervalSince1970, x: text), at: 0)
        if st.log.count > 80 { st.log.removeLast(st.log.count - 80) }
    }

    static func shortPath(_ p: String?) -> String {
        guard let p = p, !p.isEmpty else { return "un archivo" }
        let parts = p.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }

    static func clip(_ s: String, _ n: Int) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ")
        return one.count > n ? String(one.prefix(n)) + "…" : one
    }

    static func describe(_ tool: String, _ input: [String: Any], past: Bool) -> String {
        let file = input["file_path"] as? String ?? input["notebook_path"] as? String
        switch tool {
        case "Bash":
            let c = (input["description"] as? String) ?? (input["command"] as? String) ?? "un comando"
            return (past ? "Ejecutó: " : "Ejecutando: ") + clip(c, 60)
        case "Edit", "MultiEdit", "NotebookEdit":
            return (past ? "Editó " : "Editando ") + shortPath(file)
        case "Write":
            return (past ? "Escribió " : "Escribiendo ") + shortPath(file)
        case "Read":
            return (past ? "Leyó " : "Leyendo ") + shortPath(file)
        case "Grep", "Glob":
            let q = (input["pattern"] as? String) ?? ""
            return (past ? "Buscó " : "Buscando ") + "«" + clip(q, 40) + "»"
        case "WebSearch":
            return (past ? "Buscó en la web: " : "Buscando en la web: ") + clip((input["query"] as? String) ?? "", 50)
        case "WebFetch":
            return (past ? "Leyó una página web" : "Leyendo una página web")
        case "Agent", "Task":
            let d = (input["description"] as? String) ?? "una tarea"
            return (past ? "Subagente terminó: " : "Lanzando subagente: ") + clip(d, 50)
        case "TodoWrite", "TaskCreate", "TaskUpdate":
            return past ? "Actualizó su lista de tareas" : "Organizando sus tareas"
        case "Skill":
            return (past ? "Usó la skill " : "Usando la skill ") + ((input["skill"] as? String) ?? "")
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.components(separatedBy: "__")
                let server = parts.count > 1 ? parts[1].replacingOccurrences(of: "claude_ai_", with: "").replacingOccurrences(of: "plugin_", with: "") : "MCP"
                let name = parts.count > 2 ? parts[2...].joined(separator: "__") : tool
                return (past ? "Usó " : "Usando ") + name + " (" + server + ")"
            }
            return (past ? "Usó " : "Usando ") + (tool.isEmpty ? "una herramienta" : tool)
        }
    }
}
