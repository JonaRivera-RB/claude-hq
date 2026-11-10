import AppKit
import SwiftUI

// Claude HQ también funciona como comando para Claude Code:
//   ClaudeHQ hook        → lo llaman los hooks (lee JSON por stdin, no imprime nada)
//   ClaudeHQ statusline  → status line (encadena la que ya tenías y agrega tus límites)
//   ClaudeHQ install | uninstall | dump
let args = CommandLine.arguments
if args.count > 1 {
    switch args[1] {
    case "hook":
        HookHandler.run()
        exit(0)
    case "statusline":
        StatuslineHandler.run()
        exit(0)
    case "install":
        do { try Installer.install(); print("Claude HQ conectado con Claude Code.") } catch { print("Error: \(error)"); exit(1) }
        exit(0)
    case "uninstall":
        do { try Installer.uninstall(); print("Claude HQ desconectado de Claude Code.") } catch { print("Error: \(error)"); exit(1) }
        exit(0)
    case "snapshot":
        let out = args.count > 2 ? args[2] : "/tmp/claudehq.png"
        let mode = args.count > 3 ? args[3] : "compact"
        let js = args.count > 4 ? args[4] : ""
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let snap = DebugSnapshot(out: out, mode: mode, extraJS: js)
        snap.start()
        app.run()
        exit(0)
    case "cardsnap":
        let out = args.count > 2 ? args[2] : "/tmp/card.png"
        let medium = args.count > 3 && args[3] == "medium"
        MainActor.assumeIsolated {
            let view = HQCardView(snap: HQSnapshot.load(), medium: medium)
                .padding(14).frame(width: medium ? 344 : 164, height: 164, alignment: .topLeading).background(PX.bg)
            let r = ImageRenderer(content: view); r.scale = 2
            if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
               let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: out)); print("ok") }
        }
        exit(0)
    case "focus":
        if args.count > 2 {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.jonarivera.ClaudeHQ.focus"), object: args[2], userInfo: nil, deliverImmediately: true)
        }
        exit(0)
    case "dump":
        let store = DataStore()
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(store.refresh()) { print(String(decoding: d, as: UTF8.self)) }
        exit(0)
    default:
        break
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
