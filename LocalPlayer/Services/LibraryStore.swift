import Foundation
import Combine

final class LibraryStore: ObservableObject {
    @Published private(set) var allItems: [VideoItem] = []
    @Published private(set) var folders: [String] = []
    @Published var query: String = ""
    /// nil 表示根目录
    @Published var currentFolder: String?
    @Published private(set) var totalSize: Int64 = 0

    let documents: URL

    init() {
        documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        reload()
    }

    // MARK: - 扫描

    func reload() {
        let fm = FileManager.default
        var items: [VideoItem] = []
        var folderSet = Set<String>()

        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        let enumerator = fm.enumerator(
            at: documents,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                let relative = url.path.replacingOccurrences(of: documents.path + "/", with: "")
                if !relative.isEmpty, !relative.hasPrefix(".") {
                    folderSet.insert(relative)
                }
                continue
            }
            if values?.isHidden == true { continue }
            if let item = VideoItem(url: url, documents: documents) {
                items.append(item)
            }
        }

        items.sort { $0.modified > $1.modified }
        allItems = items
        folders = folderSet.sorted()
        totalSize = items.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - 派生数据

    /// 当前目录下的视频（未排序，排序交给视图，因为「最近播放」需要 ProgressStore）
    var items: [VideoItem] {
        let folder = currentFolder ?? ""
        return allItems.filter { item in
            guard item.folder == folder else { return false }
            if query.isEmpty { return true }
            return item.name.localizedCaseInsensitiveContains(query)
        }
    }

    /// 当前目录下的直接子文件夹
    var subfolders: [String] {
        let parent = currentFolder ?? ""
        return folders.filter { path in
            (path as NSString).deletingLastPathComponent == parent
        }
    }

    /// 面包屑
    var breadcrumbs: [String] {
        guard let current = currentFolder, !current.isEmpty else { return [] }
        var result: [String] = []
        var accumulated: [String] = []
        for component in current.components(separatedBy: "/") {
            accumulated.append(component)
            result.append(accumulated.joined(separator: "/"))
        }
        return result
    }

    var isEmpty: Bool { allItems.isEmpty && folders.isEmpty }

    // MARK: - 导入 / 删除

    /// 返回成功导入的数量
    @discardableResult
    func importURLs(_ urls: [URL]) -> Int {
        var count = 0
        let target = currentFolder.map { documents.appendingPathComponent($0) } ?? documents
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let destination = FileManager.default.uniqueURL(in: target, preferredName: url.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                count += 1
            } catch {
                // 忽略单个文件失败，继续下一个
            }
        }
        if count > 0 { reload() }
        return count
    }

    func delete(_ item: VideoItem) {
        try? FileManager.default.removeItem(at: item.url)
        reload()
    }

    /// 真的改磁盘上的文件名（扩展名保留）。成功返回重命名后的条目，失败返回 nil。
    func rename(_ item: VideoItem, to newBase: String) -> VideoItem? {
        let trimmed = newBase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let ext = item.ext
        let target = item.url
            .deletingLastPathComponent()
            .appendingPathComponent(trimmed)
            .appendingPathExtension(ext)
        if target.path == item.url.path { return item }

        do {
            try FileManager.default.moveItem(at: item.url, to: target)
        } catch {
            return nil
        }

        reload()
        let relative = target.path.replacingOccurrences(of: documents.path + "/", with: "")
        return VideoItem(url: target, documents: documents) ?? allItems.first { $0.relativePath == relative }
    }

    func createFolder(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let base = currentFolder.map { documents.appendingPathComponent($0) } ?? documents
        let target = base.appendingPathComponent(trimmed)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        reload()
    }
}
