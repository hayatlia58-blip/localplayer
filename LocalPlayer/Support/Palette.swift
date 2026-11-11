import SwiftUI

/// 界面色板。数值与 preview/ui-v3.html 的 :root 一一对应，改这里等于改原型。
enum Palette {
    /// #0A0A0B
    static let background = Color(red: 10 / 255, green: 10 / 255, blue: 11 / 255)

    /// 系统蓝 #0A84FF
    static let accent = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)

    /// #EBEBF0
    static let text = Color(red: 235 / 255, green: 235 / 255, blue: 240 / 255)
    /// rgba(235,235,240,.58)
    static let secondaryText = text.opacity(0.58)
    /// rgba(235,235,240,.34)
    static let tertiaryText = text.opacity(0.34)

    /// #FF453A
    static let danger = Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)

    /// 分隔线：rgba(255,255,255,.10)
    static let hairline = Color.white.opacity(0.10)

    /// 菜单里那一层极淡的选中底色
    static let rowHighlight = Color.white.opacity(0.08)
}
