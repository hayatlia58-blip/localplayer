import Foundation
import CoreFoundation

struct SubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

enum SubtitleParser {

    /// 带编码回落的解码：UTF-8 → GB18030 → UTF-16 → Latin1
    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return stripBOM(text) }

        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let text = String(data: data, encoding: gb18030) { return stripBOM(text) }
        if let text = String(data: data, encoding: .utf16) { return stripBOM(text) }
        if let text = String(data: data, encoding: .isoLatin1) { return stripBOM(text) }
        return ""
    }

    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    static func parse(url: URL) -> [SubtitleCue] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let text = decode(data)
        let ext = url.pathExtension.lowercased()
        if ext == "ass" || ext == "ssa" {
            return parseASS(text)
        }
        return parseSRT(text)
    }

    // MARK: - SRT / VTT

    static func parseSRT(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard line.contains("-->") else {
                index += 1
                continue
            }
            let parts = line.components(separatedBy: "-->")
            guard parts.count >= 2 else {
                index += 1
                continue
            }
            let start = parseTime(parts[0])
            // 右半部分可能带 VTT 的定位参数，取第一个空白段
            let rightRaw = parts[1].trimmingCharacters(in: .whitespaces)
            let rightToken = rightRaw.components(separatedBy: " ").first ?? rightRaw
            let end = parseTime(rightToken)

            var body: [String] = []
            index += 1
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                body.append(lines[index])
                index += 1
            }

            if let start, let end {
                let content = clean(body.joined(separator: "\n"))
                if !content.isEmpty {
                    cues.append(SubtitleCue(start: start, end: end, text: content))
                }
            }
            index += 1
        }
        return cues.sorted { $0.start < $1.start }
    }

    // MARK: - ASS / SSA

    static func parseASS(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var fields: [String] = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("format:") {
                fields = line.dropFirst("format:".count)
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                continue
            }
            guard line.lowercased().hasPrefix("dialogue:") else { continue }
            let payload = String(line.dropFirst("dialogue:".count))
            // 文本里可能含逗号，按字段数切分，最后一段整体作为 Text
            let limit = max(fields.count - 1, 0)
            var pieces = payload.components(separatedBy: ",")
            if pieces.count > fields.count {
                let head = pieces.prefix(limit)
                let tail = pieces.dropFirst(limit).joined(separator: ",")
                pieces = Array(head) + [tail]
            }
            guard pieces.count >= fields.count else { continue }

            func value(_ name: String) -> String? {
                guard let i = fields.firstIndex(of: name), i < pieces.count else { return nil }
                return pieces[i].trimmingCharacters(in: .whitespaces)
            }

            guard let start = parseTime(value("start") ?? ""),
                  let end = parseTime(value("end") ?? ""),
                  let raw = value("text") else { continue }

            let content = clean(raw.replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\h", with: " "))
            if !content.isEmpty {
                cues.append(SubtitleCue(start: start, end: end, text: content))
            }
        }
        return cues.sorted { $0.start < $1.start }
    }

    // MARK: - Helpers

    /// "00:01:02,500" / "00:01:02.500" / "01:02.5" -> 秒
    static func parseTime(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        // 去掉 ASS 里可能出现的额外内容
        if let space = text.firstIndex(of: " ") { text = String(text[..<space]) }
        guard !text.isEmpty else { return nil }

        let parts = text.components(separatedBy: ":")
        var seconds = 0.0
        for (i, part) in parts.enumerated() {
            guard let value = Double(part) else { return nil }
            let power = parts.count - 1 - i
            seconds += value * pow(60, Double(power))
        }
        return seconds
    }

    /// 去掉字幕样式标签，只保留纯文本
    private static func clean(_ text: String) -> String {
        var result = text

        // ASS 覆盖标签 {\an8} {\pos(..)} —— 只在找到 { 之后的位置找 }，避免死循环
        while let open = result.firstIndex(of: "{"),
              let close = result[open...].firstIndex(of: "}") {
            result.removeSubrange(open...close)
        }

        // 简单 HTML 标签 <i> </i> <font color="..">
        while let open = result.firstIndex(of: "<"),
              let close = result[open...].firstIndex(of: ">"),
              close > open {
            result.removeSubrange(open...close)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 二分查找当前时间点对应的字幕
    static func cue(at time: Double, in cues: [SubtitleCue]) -> SubtitleCue? {
        guard !cues.isEmpty else { return nil }
        var low = 0
        var high = cues.count - 1
        var candidate: Int?
        while low <= high {
            let mid = (low + high) / 2
            if cues[mid].start <= time {
                candidate = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard let index = candidate else { return nil }
        // 相邻几条可能有重叠，往回找一条仍然有效的
        var i = index
        while i >= 0 {
            let cue = cues[i]
            if time >= cue.start && time <= cue.end { return cue }
            if time - cues[i].end > 2 { break }
            i -= 1
        }
        return nil
    }
}
