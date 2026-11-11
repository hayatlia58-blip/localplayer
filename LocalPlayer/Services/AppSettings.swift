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
}
