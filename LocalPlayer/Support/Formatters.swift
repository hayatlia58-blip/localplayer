import Foundation
import UIKit

enum Fmt {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB]
        return f
    }()

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d"
        return f
    }()

    static func size(_ value: Int64) -> String {
        bytes.string(fromByteCount: value)
    }

    /// 秒 -> 00:00 / 0:00:00
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

extension FileManager {
    /// 在目录内生成不重复的文件 URL（重名则追加 " (2)"）
    func uniqueURL(in directory: URL, preferredName: String) -> URL {
        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(preferredName)
        var index = 2
        while fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}
