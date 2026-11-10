import AppKit
import SwiftUI

/// Widget de escritorio propio: una tarjeta que vive sobre el escritorio (debajo de tus ventanas),
/// se puede arrastrar y abre la oficina con un clic. No depende de WidgetKit.
final class DesktopWidgetModel: ObservableObject {
    @Published var snap: HQSnapshot?
}

private struct DesktopCard: View {
    @ObservedObject var model: DesktopWidgetModel
    let medium: Bool
    var onOpen: () -> Void
    var body: some View {
        HQCardView(snap: model.snap, medium: medium)
            .padding(14)
            .frame(width: medium ? 344 : 164, height: 164, alignment: .topLeading)
            .background(PX.bg)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(count: 1, perform: onOpen)
            .help("Clic para abrir la oficina · arrastra para moverlo")
    }
}

final class DesktopWidget {
    enum Size: String { case none, small, medium }
    private var window: NSPanel?
    private let model = DesktopWidgetModel()
    private(set) var size: Size = .none
    var onOpen: () -> Void = {}

    func update(_ snap: HQSnapshot?) { model.snap = snap }

    func set(_ newSize: Size) {
        size = newSize
        UserDefaults.standard.set(newSize.rawValue, forKey: "desktopWidget")
        window?.orderOut(nil)
        window = nil
        guard newSize != .none else { return }
        let medium = newSize == .medium
        let w: CGFloat = medium ? 344 : 164
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: 164),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: DesktopCard(model: model, medium: medium, onOpen: { [weak self] in self?.onOpen() }))
        host.frame = p.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        let key = "desktopWidgetOrigin-\(newSize.rawValue)"
        if let s = UserDefaults.standard.string(forKey: key) {
            p.setFrameOrigin(NSPointFromString(s))
        } else if let screen = NSScreen.main {
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.minX + 24, y: v.maxY - 164 - 24))
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { _ in
            UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: key)
        }
        p.orderFront(nil)
        window = p
    }

    func restore() {
        let s = Size(rawValue: UserDefaults.standard.string(forKey: "desktopWidget") ?? "small") ?? .small
        set(s)
    }
}
