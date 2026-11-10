import Foundation

/// Suma los tokens de hoy leyendo los transcripts locales de Claude Code de forma incremental.
/// Solo lee archivos; no hace llamadas a ningún servicio.
final class TranscriptScanner {
    struct Totals {
        var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
        var headline: Int { input + output + cacheWrite }
        mutating func add(_ o: Totals) { input += o.input; output += o.output; cacheWrite += o.cacheWrite; cacheRead += o.cacheRead }
    }
    struct LastInfo { var model: String?; var contextTokens: Int; var at: Double }

    private var offsets: [String: UInt64] = [:]
    private var seen = Set<String>()
    private var day: Date = Calendar.current.startOfDay(for: Date())
    private(set) var today = Totals()
    private(set) var perSession: [String: Totals] = [:]
    private(set) var perModel: [String: Totals] = [:]
    private(set) var last: [String: LastInfo] = [:]
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private let isoNoFrac = ISO8601DateFormatter()

    func scan() {
        let start = Calendar.current.startOfDay(for: Date())
        if start != day {
            day = start; offsets = [:]; seen = []; today = Totals(); perSession = [:]; perModel = [:]
        }
        let fm = FileManager.default
        guard let en = fm.enumerator(at: URL(fileURLWithPath: HQPaths.claudeProjectsDir),
                                     includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                     options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in en {
            guard url.pathExtension == "jsonl" else { continue }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let mod = vals?.contentModificationDate, mod >= start else { continue }
            let size = UInt64(vals?.fileSize ?? 0)
            let path = url.path
            let from = offsets[path] ?? 0
            if size <= from { continue }
            readLines(path: path, from: from, size: size, dayStart: start)
        }
    }

    private func readLines(path: String, from: UInt64, size: UInt64, dayStart: Date) {
        guard let fh = FileHandle(forReadingAtPath: path) else { return }
        defer { try? fh.close() }
        try? fh.seek(toOffset: from)
        guard let data = try? fh.read(upToCount: Int(size - from)), !data.isEmpty else { return }
        // Solo procesamos hasta el último salto de línea completo.
        guard let lastNL = data.lastIndex(of: 0x0A) else { return }
        offsets[path] = from + UInt64(lastNL - data.startIndex + 1)
        let chunk = data[data.startIndex...lastNL]
        let marker = Data("\"assistant\"".utf8)
        for line in chunk.split(separator: 0x0A) {
            guard line.range(of: marker) != nil,
                  let o = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  (o["type"] as? String) == "assistant",
                  let msg = o["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any] else { continue }
            let ts = (o["timestamp"] as? String).flatMap { iso.date(from: $0) ?? isoNoFrac.date(from: $0) } ?? Date()
            let sid = (o["sessionId"] as? String) ?? ""
            let model = msg["model"] as? String
            func n(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
            let ctx = n("input_tokens") + n("cache_creation_input_tokens") + n("cache_read_input_tokens")
            let sidechain = (o["isSidechain"] as? Bool) ?? false
            if !sid.isEmpty, !sidechain, model != "<synthetic>" {
                let prev = last[sid]
                if prev == nil || prev!.at <= ts.timeIntervalSince1970 {
                    last[sid] = LastInfo(model: model, contextTokens: ctx, at: ts.timeIntervalSince1970)
                }
            }
            guard ts >= dayStart else { continue }
            let key = (msg["id"] as? String) ?? (o["requestId"] as? String) ?? (o["uuid"] as? String) ?? UUID().uuidString
            if seen.contains(key) { continue }
            seen.insert(key)
            var t = Totals()
            t.input = n("input_tokens"); t.output = n("output_tokens")
            t.cacheWrite = n("cache_creation_input_tokens"); t.cacheRead = n("cache_read_input_tokens")
            today.add(t)
            if !sid.isEmpty { perSession[sid, default: Totals()].add(t) }
            if let m = model, m != "<synthetic>" { perModel[TranscriptScanner.family(m), default: Totals()].add(t) }
        }
    }

    static func family(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        if m.contains("fable") { return "Fable" }
        return "Otro"
    }

    /// "claude-opus-5-5" → "Opus 5.5"
    static func displayName(_ id: String) -> String {
        let fam = family(id)
        let nums: [String] = id.components(separatedBy: "-").filter { !$0.isEmpty && $0.count <= 2 && $0.allSatisfy { $0.isNumber } }
        if nums.count >= 2 { return "\(fam) \(nums[0]).\(nums[1])" }
        if nums.count == 1 { return "\(fam) \(nums[0])" }
        return fam
    }
}
