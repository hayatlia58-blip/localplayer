import AVFoundation
import AVKit

/// 画中画：AVPlayerLayer 才支持，必须在 Info.plist 打开 audio 后台模式
final class PiPManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published private(set) var isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    @Published private(set) var isActive = false

    private var controller: AVPictureInPictureController?

    func attach(layer: AVPlayerLayer) {
        guard controller == nil else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller
    }

    var canStart: Bool {
        (controller?.isPictureInPicturePossible ?? false)
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isActive = false
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        isActive = false
    }
}
