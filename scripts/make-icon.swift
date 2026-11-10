// Genera el ícono pixel de Claude HQ (AppIcon.icns) sin dependencias.
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .none
    // Fondo: cuadrado redondeado estilo macOS
    let inset = s * 0.1
    let r = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    NSColor(srgbRed: 0x1B/255, green: 0x1D/255, blue: 0x2E/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225).fill()
    // Personaje 12x14 centrado (mismo sprite que la oficina)
    let grid = r.width / 18
    let ox = r.minX + (r.width - grid * 12) / 2
    let oy = r.minY + (r.height - grid * 14) / 2 + grid * 0.9
    func cell(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: NSColor) {
        c.setFill()
        NSRect(x: ox + CGFloat(x) * grid, y: oy + CGFloat(14 - y - h) * grid, width: CGFloat(w) * grid, height: CGFloat(h) * grid).fill()
    }
    let hair = NSColor(srgbRed: 0x4B/255, green: 0x2E/255, blue: 0x1E/255, alpha: 1)
    let skin = NSColor(srgbRed: 0xF2/255, green: 0xC9/255, blue: 0xA0/255, alpha: 1)
    let clay = NSColor(srgbRed: 0xD9/255, green: 0x77/255, blue: 0x57/255, alpha: 1)
    let ink = NSColor(srgbRed: 0x1B/255, green: 0x1D/255, blue: 0x2E/255, alpha: 1)
    let legs = NSColor(srgbRed: 0x2A/255, green: 0x2D/255, blue: 0x44/255, alpha: 1)
    let gold = NSColor(srgbRed: 1, green: 0xD1/255, blue: 0x66/255, alpha: 1)
    cell(3, 0, 6, 2, hair); cell(2, 1, 1, 2, hair)
    cell(3, 2, 6, 4, skin)
    cell(4, 3, 1, 1, ink); cell(7, 3, 1, 1, ink)
    cell(2, 6, 8, 5, clay); cell(5, 6, 2, 1, NSColor(srgbRed: 1, green: 0.95, blue: 0.9, alpha: 1))
    cell(1, 7, 1, 3, skin); cell(10, 6, 1, 3, skin)
    cell(3, 11, 2, 3, legs); cell(7, 11, 2, 3, legs)
    // Barra de energía dorada debajo
    let bar = NSRect(x: ox - grid, y: r.minY + grid * 1.2, width: grid * 14, height: grid * 1.2)
    NSColor(srgbRed: 0x11/255, green: 0x12/255, blue: 0x1C/255, alpha: 1).setFill(); bar.fill()
    gold.setFill(); NSRect(x: bar.minX + grid * 0.25, y: bar.minY + grid * 0.25, width: bar.width * 0.6, height: bar.height - grid * 0.5).fill()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
print("ok")
