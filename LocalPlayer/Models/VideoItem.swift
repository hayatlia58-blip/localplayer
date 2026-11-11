import Foundation

struct VideoItem: Identifiable, Hashable {
    let url: URL
    /// 相对 Documents 的路径，同时作为稳定 ID（用于记录播放进度）
    let relativePath: String
    let name: String
    /// 相对文件夹路径，根目录为空字符串
    let folder: String
    let fileSize: Int64
    let modified: Date
    let ext: String

    var id: String { relativePath }

    var displayName: String { (name as NSString).deletingPathExtension }

    /// 系统原生解码（AVPlayer）能直接播的容器
    static let systemExtensions: Set<String> = [
        "mp4", "mov", "m4v", "3gp", "m2ts", "ts", "mpg", "mpeg"
    ]

    /// 列表里愿意展示的所有视频扩展名
    static let videoExtensions: Set<String> = systemExtensions.union([
        "mkv", "avi", "wmv", "flv", "webm", "rmvb", "rm", "ogv", "vob", "asf", "divx", "mts"
    ])

    var systemPlayable: Bool {
        VideoItem.systemExtensions.contains(ext)
    }
}

extension VideoItem {
    init?(url: URL, documents: URL) {
        let ext = url.pathExtension.lowercased()
        guard VideoItem.videoExtensions.contains(ext) else { return nil }
        let relative = url.path.replacingOccurrences(of: documents.path + "/", with: "")
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attrs[.modificationDate] as? Date) ?? Date.distantPast
        let folder = (relative as NSString).deletingLastPathComponent

        self.url = url
        self.relativePath = relative
        self.name = url.lastPathComponent
        self.folder = folder
        self.fileSize = size
        self.modified = modified
        self.ext = ext
    }
}

/// 排序依据：⋯ 菜单里的三选一
enum SortKey: String, CaseIterable, Identifiable {
    case recent, name, added

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "最近播放"
        case .name: return "名称"
        case .added: return "添加日期"
        }
    }
}

/// 播放模式：单集循环 / 列表循环 / 播完暂停
enum PlayMode: String, CaseIterable, Identifiable {
    case loopAll, loopOne, stopAtEnd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loopAll: return "列表循环"
        case .loopOne: return "单集循环"
        case .stopAtEnd: return "播完暂停"
        }
    }

    var shortTitle: String {
        switch self {
        case .loopAll: return "列表循环"
        case .loopOne: return "单集循环"
        case .stopAtEnd: return "播完暂停"
        }
    }
}
