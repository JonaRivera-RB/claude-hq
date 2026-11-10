import AppKit

/// Detecta en qué app corre cada sesión (recorriendo el árbol de procesos) y la trae al frente.
struct HostApp {
    var name: String
    var bundleId: String
    var appPath: String
}

enum TerminalFocus {
    struct Proc { var ppid: Int32; var comm: String; var tty: String }

    /// Una sola llamada a ps por refresco.
    static func processTable() -> [Int32: Proc] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,ppid=,tty=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var table: [Int32: Proc] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            // `ps` rellena las columnas con espacios: hay que recortarlos o la ruta de la app no existe.
            table[pid] = Proc(ppid: ppid, comm: parts[3].trimmingCharacters(in: .whitespaces), tty: String(parts[2]))
        }
        return table
    }

    static func host(for pid: Int32, table: [Int32: Proc]) -> HostApp? {
        var cur = pid
        var outermost: String?
        var guardCount = 0
        while let pr = table[cur], cur > 1, guardCount < 64 {
            if let r = pr.comm.range(of: ".app/") {
                // Tomamos el .app más externo de la ruta (VS Code ejecuta helpers dentro de su bundle).
                outermost = String(pr.comm[..<r.lowerBound]) + ".app"
            }
            cur = pr.ppid
            guardCount += 1
        }
        guard let path = outermost else { return nil }
        let bundle = Bundle(path: path)
        let bid = bundle?.bundleIdentifier ?? ""
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return HostApp(name: friendly(name, bid), bundleId: bid, appPath: path)
    }

    static func friendly(_ name: String, _ bid: String) -> String {
        switch bid {
        case "com.googlecode.iterm2": return "iTerm2"
        case "com.apple.Terminal": return "Terminal"
        case "com.microsoft.VSCode": return "VS Code"
        case "com.todesktop.230313mzl4w4u92": return "Cursor"
        case let b where b.hasPrefix("dev.warp"): return "Warp"
        case "com.mitchellh.ghostty": return "Ghostty"
        default: return name
        }
    }

    static func tty(for pid: Int32, table: [Int32: Proc]) -> String? {
        guard let t = table[pid]?.tty, t != "??", !t.isEmpty else { return nil }
        return t.hasPrefix("/dev/") ? t : "/dev/" + t
    }

    /// Lleva al usuario a la ventana/pestaña de la sesión. Devuelve una descripción del resultado.
    /// macOS 14+ solo deja activar otra app si la nuestra está activa: nos activamos y le cedemos el foco.
    static func bringToFront(_ bundleId: String) {
        guard let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return }
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: target)
            target.activate(from: NSRunningApplication.current, options: [.activateAllWindows])
        } else {
            target.activate(options: [.activateAllWindows])
        }
    }

    @discardableResult
    static func focus(host: HostApp?, tty: String?, cwd: String?) -> String {
        guard let host = host else { return "No encontré la app de esta sesión" }
        // macOS solo cambia al escritorio (Space) de la ventana si la app destino se activa estando inactiva.
        // Si la app destino está al frente, primero nos activamos nosotros.
        hqLog("focus: bid=\(host.bundleId) tty=\(tty ?? "nil")")
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == host.bundleId {
            NSApp.activate(ignoringOtherApps: true)
        }
        var denied = false
        switch host.bundleId {
        case "com.apple.Terminal", "com.googlecode.iterm2":
            if let t = tty {
                let src = host.bundleId == "com.apple.Terminal" ? terminalScript(t) : itermScript(t)
                let r = runScriptDetailed(src)
                if r == "ok" { return "ok" }
                denied = (r == "denied")
            }
        case "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.vscodium":
            if let c = cwd {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = true
                NSWorkspace.shared.open([URL(fileURLWithPath: c)], withApplicationAt: URL(fileURLWithPath: host.appPath), configuration: cfg)
                return "ok"
            }
        default:
            break
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: host.bundleId).first != nil {
            bringToFront(host.bundleId)
            return denied ? "permiso" : "ok"
        }
        guard !host.appPath.isEmpty, FileManager.default.fileExists(atPath: host.appPath) else {
            return "No encontré la app de esta sesión"
        }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: host.appPath), configuration: .init())
        return "ok"
    }

    /// "ok", "no" (no encontró la pestaña), "denied" (sin permiso de Automatización) o "error".
    static func runScriptDetailed(_ src: String) -> String {
        var err: NSDictionary?
        let res = NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let e = err {
            let code = (e[NSAppleScript.errorNumber] as? Int) ?? 0
            hqLog("applescript error \(code): \(e[NSAppleScript.errorMessage] as? String ?? "")")
            return code == -1743 || code == -1744 ? "denied" : "error"
        }
        return res?.stringValue ?? "no"
    }

    static func runScript(_ src: String) -> Bool {
        var err: NSDictionary?
        let res = NSAppleScript(source: src)?.executeAndReturnError(&err)
        if err != nil { return false }
        return res?.stringValue == "ok"
    }

    static func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }

    /// Usa el id fijo de la ventana: reordenar la referencia del ciclo no tiene efecto en Terminal.
    static func terminalScript(_ tty: String) -> String {
        """
        tell application "Terminal"
          set wid to missing value
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(esc(tty))" then
                set wid to id of w
                set selected of t to true
                exit repeat
              end if
            end repeat
            if wid is not missing value then exit repeat
          end repeat
          if wid is missing value then return "no"
          set win to window id wid
          if miniaturized of win then set miniaturized of win to false
          set index of win to 1
          activate
          return "ok"
        end tell
        """
    }

    static func itermScript(_ tty: String) -> String {
        """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if tty of s is "\(esc(tty))" then
                  select w
                  tell t to select
                  tell s to select
                  activate
                  return "ok"
                end if
              end repeat
            end repeat
          end repeat
        end tell
        return "no"
        """
    }

    /// Abre una sesión nueva de Claude Code en la carpeta elegida.
    static func newSession(in dir: String, preferIterm: Bool) {
        let cmd = "cd " + shellQuote(dir) + " && claude"
        if preferIterm, NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil {
            _ = runScriptAny("""
            tell application "iTerm2"
              activate
              set w to (create window with default profile)
              tell current session of w to write text "\(esc(cmd))"
            end tell
            """)
        } else {
            _ = runScriptAny("""
            tell application "Terminal"
              activate
              do script "\(esc(cmd))"
            end tell
            """)
        }
    }

    static func runInTerminal(_ cmd: String) {
        _ = runScriptAny("""
        tell application "Terminal"
          activate
          do script "\(esc(cmd))"
        end tell
        """)
    }

    static func runScriptAny(_ src: String) -> Bool {
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        return err == nil
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
