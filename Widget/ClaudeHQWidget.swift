import WidgetKit
import SwiftUI

struct HQEntry: TimelineEntry {
    let date: Date
    let snap: HQSnapshot?
}

struct HQProvider: TimelineProvider {
    func placeholder(in context: Context) -> HQEntry { HQEntry(date: Date(), snap: Self.sample) }
    func getSnapshot(in context: Context, completion: @escaping (HQEntry) -> Void) {
        completion(HQEntry(date: Date(), snap: HQSnapshot.load() ?? (context.isPreview ? Self.sample : nil)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HQEntry>) -> Void) {
        let entry = HQEntry(date: Date(), snap: HQSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
    }
    static let sample = HQSnapshot(updatedAt: Date().timeIntervalSince1970,
                                   fiveHour: .init(usedPercentage: 42, resetsAt: Date().addingTimeInterval(7200).timeIntervalSince1970),
                                   sevenDay: .init(usedPercentage: 18, resetsAt: Date().addingTimeInterval(400000).timeIntervalSince1970),
                                   limitsUpdatedAt: Date().timeIntervalSince1970, tokensToday: 1_240_000,
                                   agents: [.init(id: "1", name: "web-app", model: "Opus", state: "working", now: "Editando src/app.tsx", subagents: 2),
                                            .init(id: "2", name: "api-backend", model: "Sonnet", state: "waiting", now: "Pide permiso: npm test", subagents: 0),
                                            .init(id: "3", name: "docs", model: "Haiku", state: "idle", now: "Esperando tu mensaje", subagents: 0)],
                                   account: nil, plan: "Team")
}

struct HQWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: HQEntry
    var body: some View {
        HQCardView(snap: entry.snap, medium: family != .systemSmall)
            .containerBackground(PX.bg, for: .widget)
    }
}

struct ClaudeHQWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeHQWidget", provider: HQProvider()) { entry in
            HQWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude HQ")
        .description("Tus límites de Claude y lo que hacen tus agentes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ClaudeHQWidgets: WidgetBundle {
    var body: some Widget { ClaudeHQWidget() }
}
