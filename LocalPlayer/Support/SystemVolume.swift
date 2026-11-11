import UIKit
import AVFoundation
import MediaPlayer

/// 系统音量控制（把隐藏的 MPVolumeView 滑杆挂到窗口上）
final class SystemVolume {
    static let shared = SystemVolume()

    private let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 44, height: 44))

    private init() {
        volumeView.showsRouteButton = false
        volumeView.showsVolumeSlider = true
    }

    var value: Float { AVAudioSession.sharedInstance().outputVolume }

    func set(_ newValue: Float) {
        let clamped = min(max(newValue, 0), 1)
        DispatchQueue.main.async {
            if self.volumeView.superview == nil, let window = UIApplication.shared.activeWindow {
                window.addSubview(self.volumeView)
            }
            if let slider = self.volumeView.subviews.compactMap({ $0 as? UISlider }).first {
                slider.value = clamped
                slider.sendActions(for: .touchUpInside)
            }
        }
    }
}

extension UIApplication {
    var activeWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
