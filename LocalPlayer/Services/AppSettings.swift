import SwiftUI
import Combine

/// 设置项直接落在 UserDefaults 上，读写即时生效，避免 @Published + 观察者的兼容问题
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    private func read<T>(_ key: String, _ fallback: T) -> T {
        (d.object(forKey: key) as? T) ?? fallback
    }

    private func write<T>(_ key: String, _ value: T) {
        d.set(value, forKey: key)
        objectWillChange.send()
    }

    var resumePlayback: Bool {
        get { read("resumePlayback", true) }
        set { write("resumePlayback", newValue) }
    }

    var defaultRate: Double {
        get { read("defaultRate", 1.0) }
        set { write("defaultRate", newValue) }
    }

    var autoPlayNext: Bool {
        get { read("autoPlayNext", true) }
        set { write("autoPlayNext", newValue) }
    }

    var dualSubtitle: Bool {
        get { read("dualSubtitle", false) }
        set { write("dualSubtitle", newValue) }
    }

    var autoSubtitle: Bool {
        get { read("autoSubtitle", true) }
        set { write("autoSubtitle", newValue) }
    }

    // MARK: - 字幕样式

    var subtitleFontSize: Double {
        get { read("subtitleFontSize", 20.0) }
        set { write("subtitleFontSize", newValue) }
    }

    var subtitleColorHex: String {
        get { read("subtitleColorHex", "#FFFFFF") }
        set { write("subtitleColorHex", newValue) }
    }

    var subtitleBackgroundOpacity: Double {
        get { read("subtitleBackgroundOpacity", 0.35) }
        set { write("subtitleBackgroundOpacity", newValue) }
    }

    var subtitleOutline: Bool {
        get { read("subtitleOutline", true) }
        set { write("subtitleOutline", newValue) }
    }

    var subtitleColor: Color { Color(hex: subtitleColorHex) }
}

extension Color {
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
