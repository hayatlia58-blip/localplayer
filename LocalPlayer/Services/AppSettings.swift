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

    /// 断点续播
    var resumePlayback: Bool {
        get { read("resumePlayback", true) }
        set { write("resumePlayback", newValue) }
    }

    /// 默认倍速。进入播放页时的起始值，播放页抽屉里可以临时改
    var defaultRate: Double {
        get { read("defaultRate", 1.0) }
        set { write("defaultRate", newValue) }
    }

    /// 默认播放模式：播完暂停 / 单集循环 / 列表循环
    var defaultPlayMode: PlayMode {
        get {
            let raw = read("defaultPlayMode", PlayMode.loopAll.rawValue)
            return PlayMode(rawValue: raw) ?? .loopAll
        }
        set { write("defaultPlayMode", newValue.rawValue) }
    }

    /// 界面里的排序依据
    var sortKey: SortKey {
        get {
            let raw = read("sortKey", SortKey.recent.rawValue)
            return SortKey(rawValue: raw) ?? .recent
        }
        set { write("sortKey", newValue.rawValue) }
    }

    /// 升序（true）/ 降序（false）
    var sortAscending: Bool {
        get { read("sortAscending", false) }
        set { write("sortAscending", newValue) }
    }
}
