import UIKit
import AVFoundation

/// 视频首帧缩略图，带内存缓存。MKV 等系统不支持的容器会失败，UI 侧回落到占位图。
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "localplayer.thumbnails", qos: .utility, attributes: .concurrent)
    private var inFlight = Set<String>()
    private var pending: [String: [(UIImage?) -> Void]] = [:]
    private let lock = NSLock()

    func cached(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func load(for item: VideoItem, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        if let image = cached(for: item.id) {
            completion(image)
            return
        }
        lock.lock()
        if inFlight.contains(item.id) {
            // 已经有人在生成，挂到同一个等待队列，避免重复解码
            pending[item.id, default: []].append(completion)
            lock.unlock()
            return
        }
        inFlight.insert(item.id)
        lock.unlock()

        guard item.systemPlayable else {
            lock.lock(); inFlight.remove(item.id); lock.unlock()
            completion(nil)
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            let asset = AVURLAsset(url: item.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = size
            generator.requestedTimeToleranceBefore = CMTime(seconds: 3, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 3, preferredTimescale: 600)

            var image: UIImage?
            if let cg = try? generator.copyCGImage(at: CMTime(seconds: 5, preferredTimescale: 600), actualTime: nil) {
                image = UIImage(cgImage: cg)
            } else if let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                image = UIImage(cgImage: cg)
            }

            self.lock.lock()
            self.inFlight.remove(item.id)
            let waiters = self.pending.removeValue(forKey: item.id) ?? []
            self.lock.unlock()

            if let image {
                self.cache.setObject(image, forKey: item.id as NSString)
            }
            DispatchQueue.main.async {
                completion(image)
                waiters.forEach { $0(image) }
            }
        }
    }

    func clear() {
        cache.removeAllObjects()
    }
}
