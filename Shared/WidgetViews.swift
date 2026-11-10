import SwiftUI

enum PX {
    static let bg = Color(red: 0x1B / 255, green: 0x1D / 255, blue: 0x2E / 255)
    static let deep = Color(red: 0x11 / 255, green: 0x12 / 255, blue: 0x1C / 255)
    static let cell = Color(red: 0x2B / 255, green: 0x2F / 255, blue: 0x52 / 255)
    static let ink = Color(red: 0xE8 / 255, green: 0xE9 / 255, blue: 0xF5 / 255)
    static let muted = Color(red: 0xA9 / 255, green: 0xAE / 255, blue: 0xD6 / 255)
    static let gold = Color(red: 1, green: 0xD1 / 255, blue: 0x66 / 255)
    static let mint = Color(red: 0x7F / 255, green: 0xE0 / 255, blue: 0xB4 / 255)
    static let orange = Color(red: 1, green: 0x9F / 255, blue: 0x43 / 255)
    static let red = Color(red: 1, green: 0x5D / 255, blue: 0x5D / 255)
    static func model(_ m: String) -> Color {
        switch m {
        case "Opus": return Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
        case "Sonnet": return Color(red: 0x6C / 255, green: 0x8E / 255, blue: 0xF5 / 255)
        case "Haiku": return mint
        case "Fable": return Color(red: 0xB4 / 255, green: 0x8C / 255, blue: 0xF0 / 255)
        default: return ink
        }
    }
    static func state(_ s: String) -> Color {
        switch s {
        case "working": return mint
        case "waiting": return gold
        case "error": return red
        default: return muted
        }
    }
    static func font(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size, weight: w, design: .monospaced) }
}

struct Meter: View {
    let label: String
    let window: HQSnapshot.Window?
    let base: Color
    var body: some View {
        let now = Date().timeIntervalSince1970
        let used = (window.map { $0.resetsAt > now ? $0.usedPercentage : 0 }) ?? -1
        let free = used < 0 ? 0 : max(0, Int((100 - used).rounded()))
        let color = used < 0 ? PX.muted : (free <= 5 ? PX.red : (free <= 20 ? PX.orange : base))
        let n = used < 0 ? 0 : max(free > 0 ? 1 : 0, Int((Double(free) * 12 / 100).rounded()))
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(PX.font(10, .bold)).foregroundStyle(PX.ink)
                Spacer()
                Text(used < 0 ? "--" : "\(free)% libre").font(PX.font(10, .bold)).foregroundStyle(color)
            }
            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { i in
                    Rectangle().fill(i < n ? color : PX.cell)
                }
            }
            .frame(height: 9)
            .padding(2)
            .background(PX.deep)
            if let w = window, w.resetsAt > now {
                Text("reinicia " + HQFormat.clock(w.resetsAt)).font(PX.font(9)).foregroundStyle(PX.muted)
            }
        }
    }
}

struct HQCardView: View {
    let snap: HQSnapshot?
    let medium: Bool

    var body: some View {
        let s = snap
        Group {
            if s == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CLAUDE HQ").font(PX.font(13, .bold)).foregroundStyle(PX.ink)
                    Text("Abre Claude HQ para ver tus límites y agentes.").font(PX.font(10)).foregroundStyle(PX.muted)
                }
            } else if !medium {
                small(s!)
            } else {
                mediumView(s!)
            }
        }
    }

    func header(_ s: HQSnapshot) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(PX.model("Opus")).frame(width: 10, height: 10)
            Text("CLAUDE HQ").font(PX.font(11, .bold)).foregroundStyle(PX.ink)
            Spacer()
            let waiting = s.agents.filter { $0.state == "waiting" }.count
            if waiting > 0 {
                Text("\(waiting)!").font(PX.font(10, .bold)).foregroundStyle(PX.bg)
                    .padding(.horizontal, 4).background(PX.gold)
            }
        }
    }

    func small(_ s: HQSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            header(s)
            Meter(label: "5 H", window: s.fiveHour, base: PX.gold)
            Meter(label: "SEMANA", window: s.sevenDay, base: PX.mint)
            Spacer(minLength: 0)
            Text("\(s.agents.count) agentes · \(HQFormat.tokens(s.tokensToday)) hoy").font(PX.font(9)).foregroundStyle(PX.muted)
        }
    }

    func mediumView(_ s: HQSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                header(s)
                Meter(label: "5 H", window: s.fiveHour, base: PX.gold)
                Meter(label: "SEMANA", window: s.sevenDay, base: PX.mint)
                Spacer(minLength: 0)
                Text("\(HQFormat.tokens(s.tokensToday)) tokens hoy").font(PX.font(9)).foregroundStyle(PX.muted)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 5) {
                Text("AGENTES").font(PX.font(10, .bold)).foregroundStyle(PX.muted)
                if s.agents.isEmpty {
                    Text("Oficina vacía").font(PX.font(10)).foregroundStyle(PX.muted)
                }
                ForEach(Array(s.agents.prefix(4).enumerated()), id: \.offset) { _, a in
                    HStack(spacing: 5) {
                        Rectangle().fill(PX.model(a.model)).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 3) {
                                Text(a.name).font(PX.font(10, .bold)).foregroundStyle(PX.ink).lineLimit(1)
                                if a.subagents > 0 { Text("+\(a.subagents)").font(PX.font(9)).foregroundStyle(PX.gold) }
                            }
                            Text(a.now).font(PX.font(9)).foregroundStyle(PX.state(a.state)).lineLimit(1)
                        }
                    }
                }
                if s.agents.count > 4 {
                    Text("y \(s.agents.count - 4) más").font(PX.font(9)).foregroundStyle(PX.muted)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

