import Foundation
import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

/// PhotosPicker 拿到的视频：复制到临时目录，避免把整段视频读进内存
struct MovieFile: Transferable {
    let url: URL
    let ext: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty
                ? "mov"
                : received.file.pathExtension.lowercased()
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.copyItem(at: received.file, to: temp)
            return MovieFile(url: temp, ext: ext)
        }
    }
}

enum PhotoImporter {
    /// 相册导入：文件名用「日期_流水号」，与素材命名习惯一致
    static func importItems(
        _ items: [PhotosPickerItem],
        into folder: String?,
        library: LibraryStore
    ) async -> Int {
        let documents = library.documents
        let target = folder.map { documents.appendingPathComponent($0) } ?? documents
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        var saved = 0
        for pickerItem in items {
            guard let movie = try? await pickerItem.loadTransferable(type: MovieFile.self) else { continue }
            let base = nextName(in: target)
            let destination = FileManager.default.uniqueURL(
                in: target,
                preferredName: "\(base).\(movie.ext)"
            )
            do {
                try FileManager.default.moveItem(at: movie.url, to: destination)
                saved += 1
            } catch {
                try? FileManager.default.removeItem(at: movie.url)
            }
        }
        if saved > 0 {
            await MainActor.run { library.reload() }
        }
        return saved
    }

    private static func nextName(in directory: URL) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let prefix = formatter.string(from: Date())

        var maxIndex = 0
        if let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
            for name in names where name.hasPrefix(prefix + "_") {
                let rest = name.dropFirst(prefix.count + 1)
                let digits = rest.prefix { $0.isNumber }
                if let value = Int(digits) {
                    maxIndex = max(maxIndex, value)
                }
            }
        }
        return String(format: "%@_%03d", prefix, maxIndex + 1)
    }
}
