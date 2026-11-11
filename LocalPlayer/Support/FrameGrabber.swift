import AVFoundation
import Photos
import UIKit

/// 播放页右上角那个圆形键：抓当前这一帧，存进系统相册
enum FrameGrabber {
    enum GrabError: LocalizedError {
        case noFrame
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noFrame: return "这一帧没抓到，稍等一下再试"
            case .denied: return "没有相册写入权限，去「设置」里打开"
            case .failed(let message): return message
            }
        }
    }

    static func capture(url: URL, at seconds: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)

        DispatchQueue.global(qos: .userInitiated).async {
            let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                DispatchQueue.main.async { completion(.failure(GrabError.noFrame)) }
                return
            }
            let image = UIImage(cgImage: cgImage)
            save(image, completion: completion)
        }
    }

    private static func save(_ image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(.failure(GrabError.denied)) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(()))
                    } else {
                        completion(.failure(GrabError.failed(error?.localizedDescription ?? "保存失败")))
                    }
                }
            }
        }
    }
}
