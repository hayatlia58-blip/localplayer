import UIKit

/// 屏幕亮度：优先取当前窗口所在屏幕，避免 UIScreen.main 在新系统上的警告
enum ScreenBrightness {
    private static var screen: UIScreen? {
        UIApplication.shared.activeWindow?.windowScene?.screen
    }

    static var current: CGFloat {
        screen?.brightness ?? UIScreen.main.brightness
    }

    static func set(_ value: CGFloat) {
        let clamped = min(max(value, 0), 1)
        if let screen {
            screen.brightness = clamped
        } else {
            UIScreen.main.brightness = clamped
        }
    }
}
