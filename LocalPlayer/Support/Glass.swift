import SwiftUI

/// 四层玻璃配方（对应原型里的 .glass / .menu）：
///   1. .ultraThinMaterial 提供真实的背景模糊
///   2. 一层渐变染色，把材质压到合适的明度
///   3. 0.75pt 渐变描边，上沿亮、下沿几乎看不见
///   4. 外投影，让整块浮起来
struct GlassStyle {
    var top: Color
    var bottom: Color
    var strokeTop: Color
    var strokeBottom: Color
    var shadowRadius: CGFloat
    var shadowY: CGFloat
    var shadowOpacity: Double

    /// 控件：按钮、运输胶囊、进度条胶囊
    static let control = GlassStyle(
        top: Color.white.opacity(0.13),
        bottom: Color.white.opacity(0.05),
        strokeTop: Color.white.opacity(0.22),
        strokeBottom: Color.white.opacity(0.05),
        shadowRadius: 12,
        shadowY: 4,
        shadowOpacity: 0.30
    )

    /// 菜单、抽屉、弹窗
    static let panel = GlassStyle(
        top: Color.black.opacity(0.34),
        bottom: Color.black.opacity(0.46),
        strokeTop: Color.white.opacity(0.18),
        strokeBottom: Color.white.opacity(0.04),
        shadowRadius: 28,
        shadowY: 10,
        shadowOpacity: 0.45
    )

    /// 播放条上的浅色底（比 control 再淡一点）
    static let subtle = GlassStyle(
        top: Color.white.opacity(0.10),
        bottom: Color.white.opacity(0.04),
        strokeTop: Color.white.opacity(0.18),
        strokeBottom: Color.white.opacity(0.04),
        shadowRadius: 8,
        shadowY: 3,
        shadowOpacity: 0.24
    )
}

private struct GlassFill<S: InsettableShape>: View {
    let shape: S
    let style: GlassStyle

    var body: some View {
        shape
            .fill(Material.ultraThinMaterial)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [style.top, style.bottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [style.strokeTop, style.strokeBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            }
            .compositingGroup()
            .shadow(
                color: .black.opacity(style.shadowOpacity),
                radius: style.shadowRadius,
                y: style.shadowY
            )
    }
}

extension View {
    /// 给任意形状套上玻璃底。用法：`.glass(Circle())` / `.glass(RoundedRectangle(cornerRadius: 20, style: .continuous))`
    func glass<S: InsettableShape>(_ shape: S, style: GlassStyle = .control) -> some View {
        background { GlassFill(shape: shape, style: style) }
    }

    func glass(cornerRadius: CGFloat, style: GlassStyle = .panel) -> some View {
        glass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), style: style)
    }
}

// MARK: - 圆形图标按钮

struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = 36
    var iconSize: CGFloat = 16
    var weight: Font.Weight = .medium
    var style: GlassStyle = .control
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: weight))
                .foregroundStyle(Palette.text)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(Circle(), style: style)
    }
}
