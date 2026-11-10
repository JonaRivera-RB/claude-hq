import AppKit
import WebKit

/// `ClaudeHQ snapshot <salida.png> [compact|expanded] [settings]`
/// Renderiza la interfaz con los datos reales a una imagen (para revisar el diseño sin capturar pantalla).
final class DebugSnapshot: NSObject, WKNavigationDelegate {
    let out: String
    let mode: String
    let extraJS: String
    var window: NSWindow!
    var web: WKWebView!

    init(out: String, mode: String, extraJS: String) {
        self.out = out; self.mode = mode; self.extraJS = extraJS
    }

    func start() {
        let size = mode == "expanded" ? NSSize(width: 480, height: 900) : NSSize(width: 400, height: 612)
        window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        web = WKWebView(frame: NSRect(origin: .zero, size: size))
        web.navigationDelegate = self
        window.contentView = web
        window.orderBack(nil)
        let dir = Bundle.main.resourceURL!.appendingPathComponent("web")
        web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let payload = DataStore().refresh()
        let json = (try? JSONEncoder().encode(payload)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        web.evaluateJavaScript("hq.setMode('\(mode)', true); hq.update(\(json)); \(extraJS)") { res, err in
            if let r = res { print("JS: \(r)") }
            if let err = err { print("JS error: \(err)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let cfg = WKSnapshotConfiguration()
                self.web.takeSnapshot(with: cfg) { img, err in
                    if let img = img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: self.out))
                        print("ok \(self.out)")
                    } else {
                        print("snapshot failed: \(String(describing: err))")
                    }
                    exit(0)
                }
            }
        }
    }
}
