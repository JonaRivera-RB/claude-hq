import AppKit
import WebKit
import UserNotifications
import ServiceManagement
import WidgetKit

final class HQPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Acepta el primer clic aunque la ventana no esté activa (si no, el primer clic solo la enfoca).
final class HQWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

func hqLog(_ msg: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
    let line = "\(f.string(from: Date())) \(msg)\n"
    let path = HQPaths.hqDir + "/app.log"
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var panel: HQPanel!
    private var webView: WKWebView!
    private let store = DataStore()
    private let queue = DispatchQueue(label: "claudehq.refresh", qos: .utility)
    private var refreshing = false
    private var timer: Timer?
    private var apiTimer: Timer?
    private var lastPayload: DataStore.Payload?
    private var lastSnapshotData: Data?
    private var lastWidgetReload: Double = 0
    private var prevStates: [String: String] = [:]
    private var notified = Set<String>()
    private var webReady = false
    private var expanded = false
    private var pinned = true
    private let desktopWidget = DesktopWidget()

    static let bg = NSColor(srgbRed: 0x1B / 255, green: 0x1D / 255, blue: 0x2E / 255, alpha: 1)
    static let compactSize = NSSize(width: 400, height: 640)
    static let expandedSize = NSSize(width: 480, height: 900)

    func applicationDidFinishLaunching(_ notification: Notification) {
        HQPaths.ensureDirs()
        setupStatusItem()
        setupPanel()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        apiTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.fetchAPI() }
        // Disparador de pruebas: `ClaudeHQ focus <sessionId>` envía esta notificación y la app ejecuta lo mismo que el botón.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.jonarivera.ClaudeHQ.focus"), object: nil, queue: .main) { [weak self] n in
            if let sid = n.object as? String { hqLog("test: focus \(sid)"); self?.focus(sid) }
        }
        desktopWidget.onOpen = { [weak self] in self?.showPanel() }
        desktopWidget.restore()
        refresh()
        fetchAPI()
        showPanel()
    }

    // MARK: Barra de menú

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.title = "HQ"
            b.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            b.target = self
            b.action = #selector(statusClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        if panel.isVisible { panel.orderOut(nil) } else { showPanel() }
    }

    private func showMenu() {
        let m = NSMenu()
        m.addItem(withTitle: panel.isVisible ? "Ocultar la oficina" : "Mostrar la oficina", action: #selector(togglePanel), keyEquivalent: "")
        m.addItem(.separator())
        if let p = lastPayload {
            if p.loggedIn == true, let a = p.account {
                let it = NSMenuItem(title: "\(a["email"] ?? "") · \(a["plan"] ?? "")", action: nil, keyEquivalent: "")
                it.isEnabled = false
                m.addItem(it)
            } else {
                m.addItem(withTitle: "Iniciar sesión con Claude…", action: #selector(menuLogin), keyEquivalent: "")
            }
            m.addItem(withTitle: p.installed ? "Desconectar de Claude Code" : "Conectar con Claude Code…", action: #selector(menuToggleInstall), keyEquivalent: "")
        }
        let wMenu = NSMenu()
        for (title, size) in [("Ninguno", DesktopWidget.Size.none), ("Chico", .small), ("Mediano", .medium)] {
            let it = NSMenuItem(title: title, action: #selector(setDesktopWidget(_:)), keyEquivalent: "")
            it.representedObject = size.rawValue
            it.state = desktopWidget.size == size ? .on : .off
            it.target = self
            wMenu.addItem(it)
        }
        let wItem = NSMenuItem(title: "Widget de escritorio", action: nil, keyEquivalent: "")
        wItem.submenu = wMenu
        m.addItem(wItem)
        let login = NSMenuItem(title: "Abrir al iniciar sesión en la Mac", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)
        m.addItem(.separator())
        m.addItem(withTitle: "Salir de Claude HQ", action: #selector(quit), keyEquivalent: "q")
        for i in m.items { i.target = self }
        statusItem.menu = m
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePanel() { if panel.isVisible { panel.orderOut(nil) } else { showPanel() } }
    @objc private func menuLogin() { startLogin() }
    @objc private func menuToggleInstall() { (lastPayload?.installed ?? false) ? confirmUninstall() : confirmInstall() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func setDesktopWidget(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let size = DesktopWidget.Size(rawValue: raw) {
            desktopWidget.set(size)
            if let p = lastPayload { desktopWidget.update(store.snapshot(from: p)) }
        }
    }
    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { toast("No pude cambiar el inicio automático: \(error.localizedDescription)") }
    }

    private func updateStatusTitle(_ p: DataStore.Payload) {
        guard let b = statusItem.button else { return }
        var text = "HQ"
        var color = NSColor.labelColor
        if let w = p.fiveHour, !w.expired {
            let used = Int(w.used.rounded())
            text = "5h \(used)%"
            if used >= 95 { color = .systemRed } else if used >= 80 { color = .systemOrange }
        }
        let waiting = p.agents.filter { $0.state == "waiting" }.count
        if waiting > 0 { text += " · \(waiting)!" ; if color == .labelColor { color = .systemYellow } }
        b.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: color])
    }

    // MARK: Ventana flotante

    private func setupPanel() {
        panel = HQPanel(contentRect: NSRect(origin: .zero, size: Self.compactSize),
                        styleMask: [.titled, .closable, .miniaturizable, .resizable],
                        backing: .buffered, defer: false)
        panel.title = "Claude HQ"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = Self.bg
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 360, height: 420)
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setFrameAutosaveName("ClaudeHQPanel")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - Self.compactSize.width - 24, y: v.maxY - Self.compactSize.height - 24))
        }

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "hq")
        webView = HQWebView(frame: panel.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        panel.contentView?.addSubview(webView)

        if let dir = Bundle.main.resourceURL?.appendingPathComponent("web"),
           FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.html").path) {
            webView.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
        }
    }

    private func showPanel() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func setMode(expanded e: Bool) {
        expanded = e
        let target = e ? Self.expandedSize : Self.compactSize
        var f = panel.frame
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? f
        let h = min(target.height, visible.height - 20)
        let top = f.maxY
        f.size = NSSize(width: target.width, height: h)
        f.origin.y = max(visible.minY, top - h)
        if f.maxX > visible.maxX { f.origin.x = visible.maxX - f.width }
        panel.setFrame(f, display: true, animate: true)
    }

    // MARK: Refresco

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        queue.async { [weak self] in
            guard let self = self else { return }
            let payload = self.store.refresh()
            let enc = JSONEncoder()
            let json = (try? enc.encode(payload)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            let snap = try? enc.encode(self.store.snapshot(from: payload))
            DispatchQueue.main.async {
                self.refreshing = false
                self.lastPayload = payload
                self.updateStatusTitle(payload)
                if self.webReady { self.webView.evaluateJavaScript("window.hq && hq.update(\(json))") }
                self.checkAlerts(payload)
                self.writeSnapshot(snap)
                self.desktopWidget.update(self.store.snapshot(from: payload))
            }
        }
    }

    private func writeSnapshot(_ data: Data?) {
        guard let data = data else { return }
        hqWriteAtomic(data, to: HQPaths.snapshotFile)
        // Recargamos el widget solo cuando cambia algo visible, como máximo una vez por minuto.
        let now = Date().timeIntervalSince1970
        var stripped = data
        if var o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            o["updatedAt"] = 0
            stripped = (try? JSONSerialization.data(withJSONObject: o, options: .sortedKeys)) ?? data
        }
        if stripped != lastSnapshotData, now - lastWidgetReload > 60 {
            lastSnapshotData = stripped
            lastWidgetReload = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func fetchAPI() {
        guard let key = Keychain.load() else { store.api = nil; store.apiConfigured = false; return }
        store.apiConfigured = true
        Task {
            let r = await AdminAPI.fetch(key: key)
            await MainActor.run { self.store.api = r; self.refresh() }
        }
    }

    // MARK: Alertas (80% y 95%, permisos y errores)

    private func checkAlerts(_ p: DataStore.Payload) {
        defer { prevStates = Dictionary(uniqueKeysWithValues: p.agents.map { ($0.id, $0.state) }) }
        guard p.alertsEnabled else { return }
        for (label, w) in [("5 horas", p.fiveHour), ("semanal", p.sevenDay)] {
            guard let w = w, !w.expired else { continue }
            for th in [95, 80] where w.used >= Double(th) {
                let key = "\(label)-\(th)-\(Int(w.resetsAt))"
                if !notified.contains(key) {
                    notified.insert(key)
                    if th == 95 { notified.insert("\(label)-80-\(Int(w.resetsAt))") }
                    notify(title: th >= 95 ? "Casi sin límite \(label)" : "Llevas \(th)% del límite \(label)",
                           body: "Te queda \(max(0, 100 - Int(w.used.rounded())))%. Se reinicia \(HQFormat.clock(w.resetsAt)).",
                           sid: nil)
                }
                break
            }
        }
        guard !prevStates.isEmpty else { return }
        for a in p.agents {
            let prev = prevStates[a.id]
            if a.state == "waiting", prev != nil, prev != "waiting" {
                notify(title: "\(a.name) necesita tu permiso", body: a.now, sid: a.id)
            } else if a.state == "error", prev != nil, prev != "error" {
                notify(title: "\(a.name) se detuvo", body: a.now, sid: a.id)
            }
        }
    }

    private func notify(title: String, body: String, sid: String?) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = HQConfig.load().soundEnabled ? .default : nil
        if let s = sid { c.userInfo = ["sid": s] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let sid = response.notification.request.content.userInfo["sid"] as? String {
            DispatchQueue.main.async { self.focus(sid) }
        }
        completionHandler()
    }

    // MARK: Puente con la interfaz

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webReady = true
        if let p = lastPayload, let d = try? JSONEncoder().encode(p) {
            webView.evaluateJavaScript("window.hq && hq.update(\(String(decoding: d, as: UTF8.self)))")
        }
        webView.evaluateJavaScript("window.hq && hq.setMode(\(expanded ? "'expanded'" : "'compact'"), \(pinned))")
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action != "saveKey" { hqLog("ui: \(action) \(body["id"] as? String ?? "")") }
        switch action {
        case "focus":
            if let id = body["id"] as? String { focus(id) }
        case "newSession":
            newSession()
        case "setModel":
            if let m = body["model"] as? String {
                do { try ClaudeSettings.setModel(m.lowercased()); toast("Modelo por defecto: \(m). Aplica a sesiones nuevas.") }
                catch { toast("No pude guardar el modelo") }
                refresh()
            }
        case "setPerm":
            if let m = body["mode"] as? String {
                do { try ClaudeSettings.setPermissionMode(m); toast("Permisos por defecto actualizados. Aplica a sesiones nuevas.") }
                catch { toast("No pude guardar los permisos") }
                refresh()
            }
        case "mode":
            setMode(expanded: (body["value"] as? String) == "expanded")
        case "pin":
            pinned = (body["value"] as? Bool) ?? true
            panel.level = pinned ? .floating : .normal
        case "login":
            startLogin()
        case "logout":
            confirmLogout()
        case "install":
            confirmInstall()
        case "uninstall":
            confirmUninstall()
        case "saveKey":
            if let k = (body["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty {
                if Keychain.save(k) { toast("API key guardada en el Llavero"); fetchAPI() } else { toast("No pude guardar la key") }
            }
        case "clearKey":
            Keychain.delete()
            store.api = nil
            store.apiConfigured = false
            toast("API key borrada del Llavero")
            refresh()
        case "alerts":
            var c = HQConfig.load(); c.alertsEnabled = (body["value"] as? Bool) ?? true; c.save(); refresh()
        case "sound":
            var c = HQConfig.load(); c.soundEnabled = (body["value"] as? Bool) ?? true; c.save(); refresh()
        case "openURL":
            if let s = body["url"] as? String, let u = URL(string: s), u.scheme == "https" { NSWorkspace.shared.open(u) }
        case "desktopWidget":
            if let raw = body["value"] as? String, let size = DesktopWidget.Size(rawValue: raw) {
                desktopWidget.set(size)
                if let p = lastPayload { desktopWidget.update(store.snapshot(from: p)) }
                toast(size == .none ? "Widget de escritorio oculto" : "Widget en tu escritorio. Arrástralo a donde quieras.")
            }
        case "hide":
            panel.orderOut(nil)
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    private func toast(_ text: String) {
        let esc = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.hq && hq.toast('\(esc)')")
    }

    private func focus(_ sid: String) {
        guard let (host, tty, cwd) = store.hosts[sid] else {
            hqLog("focus: sin datos de host para \(sid)")
            toast("Esa sesión ya no está abierta"); return
        }
        let name = lastPayload?.agents.first { $0.id == sid }?.name ?? "esa sesión"
        let app = host?.name ?? "la terminal"
        // ¿Ya estaba al frente esa pestaña? (para avisarlo en vez de parecer que no pasó nada)
        var alreadyThere = false
        if host?.bundleId == "com.apple.Terminal", let t = tty,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal" {
            var err: NSDictionary?
            let cur = NSAppleScript(source: "tell application \"Terminal\" to get tty of selected tab of window 1")?.executeAndReturnError(&err).stringValue
            alreadyThere = (cur == t)
        }
        let r = TerminalFocus.focus(host: host, tty: tty, cwd: cwd)
        hqLog("focus: app=\(host?.name ?? "?") tty=\(tty ?? "?") → \(r)")
        if r == "ok" {
            toast(alreadyThere ? "Ya estás en la pestaña de \(name) en \(app)" : "Listo: abrí la pestaña de \(name) en \(app)")
        }
        if r == "permiso" {
            toast("Dale permiso a Claude HQ en Ajustes del Sistema › Privacidad › Automatización")
        } else if r != "ok" { toast(r) }
    }

    private func newSession() {
        let op = NSOpenPanel()
        op.canChooseDirectories = true
        op.canChooseFiles = false
        op.prompt = "Abrir Claude aquí"
        op.message = "Elige la carpeta del proyecto para la nueva sesión"
        NSApp.activate(ignoringOtherApps: true)
        if op.runModal() == .OK, let url = op.url {
            let iterm = (lastPayload?.agents.filter { $0.app == "iTerm2" }.count ?? 0) > (lastPayload?.agents.filter { $0.app == "Terminal" }.count ?? 0)
            TerminalFocus.newSession(in: url.path, preferIterm: iterm)
        }
    }

    private func startLogin() {
        TerminalFocus.runInTerminal(ClaudeCLI.loginCommand)
        toast("Completa el login en el navegador que se abrió")
        // Revisamos la cuenta seguido durante unos minutos.
        for i in 1...18 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(i * 10)) { [weak self] in
                self?.store.forceAccountRefresh(); self?.refresh()
            }
        }
    }

    private func confirmLogout() {
        let a = NSAlert()
        a.messageText = "¿Cerrar sesión de Claude?"
        a.informativeText = "Esto cierra la sesión de Claude Code en esta Mac (es el mismo login). Tus sesiones abiertas pueden dejar de funcionar hasta que vuelvas a entrar."
        a.addButton(withTitle: "Cerrar sesión")
        a.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            queue.async { ClaudeCLI.logout(); DispatchQueue.main.async { self.store.forceAccountRefresh(); self.refresh() } }
        }
    }

    private func confirmInstall() {
        let a = NSAlert()
        a.messageText = "Conectar Claude HQ con Claude Code"
        a.informativeText = """
        Voy a modificar ~/.claude/settings.json (guardo un respaldo en ~/.claude-hq):
        • Hooks silenciosos para saber qué hace cada sesión (no imprimen nada, no gastan tokens).
        • La status line: se conserva la que ya tienes y se le agregan tus límites de 5 h y semana.

        Aplica a las sesiones que abras o retomes después de conectar.
        """
        a.addButton(withTitle: "Conectar")
        a.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            do { try Installer.install(); toast("Conectado. Abre o retoma una sesión para ver sus datos.") }
            catch { toast("No pude conectar: \(error.localizedDescription)") }
            refresh()
        }
    }

    private func confirmUninstall() {
        let a = NSAlert()
        a.messageText = "¿Desconectar Claude HQ de Claude Code?"
        a.informativeText = "Quito los hooks de Claude HQ y restauro tu status line anterior."
        a.addButton(withTitle: "Desconectar")
        a.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            do { try Installer.uninstall(); toast("Desconectado") } catch { toast("No pude desconectar") }
            refresh()
        }
    }
}
