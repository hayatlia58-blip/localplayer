import SwiftUI

// MARK: - 通用行

struct MenuRowButton: View {
    let title: String
    var icon: String? = nil
    var checked: Bool = false
    var danger: Bool = false
    var height: CGFloat = 44
    var fontSize: CGFloat = 15.5
    var iconWidth: CGFloat = 20
    var horizontalPadding: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Group {
                    if let icon {
                        Image(systemName: checked ? "checkmark" : icon)
                            .font(.system(size: 15, weight: .medium))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: iconWidth, alignment: .center)

                Text(title)
                    .font(.system(size: fontSize))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(danger ? Palette.danger : Palette.text)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 白色圆底 + 深色符号（导入菜单专用，和 Outplayer 一致）
struct MenuBadgeRow: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white))

                Text(title)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MenuSeparator: View {
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 4

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 0.5)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
    }
}

// MARK: - 菜单容器

struct GlassMenuContainer<Content: View>: View {
    var width: CGFloat = 200
    var cornerRadius: CGFloat = 20
    var verticalPadding: CGFloat = 4
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(width: width)
            .padding(.vertical, verticalPadding)
            .glass(cornerRadius: cornerRadius, style: .panel)
    }
}

// MARK: - 导入菜单

struct ImportMenu: View {
    var onPhoto: () -> Void
    var onFile: () -> Void

    var body: some View {
        GlassMenuContainer(width: 200, verticalPadding: 4) {
            MenuBadgeRow(title: "从相册导入", icon: "photo", action: onPhoto)
            MenuBadgeRow(title: "从文件导入", icon: "folder", action: onFile)
        }
    }
}

// MARK: - 「…」菜单

struct MoreMenu: View {
    let sortKey: SortKey
    let ascending: Bool
    var onNewFolder: () -> Void
    var onSort: (SortKey) -> Void
    var onToggleOrder: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        GlassMenuContainer(width: 200) {
            MenuRowButton(title: "新建文件夹", icon: "folder.badge.plus", action: onNewFolder)

            MenuSeparator()

            ForEach(SortKey.allCases) { key in
                if sortKey == key {
                    MenuRowButton(title: key.title, icon: "checkmark", action: { onSort(key) })
                } else {
                    MenuRowButton(title: key.title, icon: nil, action: { onSort(key) })
                }
            }

            MenuSeparator()

            MenuRowButton(
                title: ascending ? "降序排列" : "升序排列",
                icon: nil,
                action: onToggleOrder
            )
            MenuRowButton(title: "刷新缩略图", icon: nil, action: onRefresh)

            Color.clear.frame(height: 4)
        }
    }
}

// MARK: - 长按菜单（锚定卡片）

struct CardMenu: View {
    let item: VideoItem
    let watched: Bool
    var onMarkWatched: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    static let width: CGFloat = 174
    static let estimatedHeight: CGFloat = 174

    var body: some View {
        VStack(spacing: 0) {
            Text(item.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.text.opacity(0.70))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 9)
                .padding(.bottom, 7)

            MenuSeparator(horizontalPadding: 10, verticalPadding: 3)

            MenuRowButton(
                title: watched ? "标记为未看" : "标记为已看",
                icon: watched ? "circle" : "checkmark.circle",
                height: 42,
                fontSize: 15,
                iconWidth: 19,
                horizontalPadding: 12,
                action: onMarkWatched
            )
            MenuRowButton(
                title: "重命名",
                icon: "character.cursor.ibeam",
                height: 42,
                fontSize: 15,
                iconWidth: 19,
                horizontalPadding: 12,
                action: onRename
            )

            MenuSeparator(horizontalPadding: 10, verticalPadding: 3)

            MenuRowButton(
                title: "删除",
                icon: "trash",
                danger: true,
                height: 42,
                fontSize: 15,
                iconWidth: 19,
                horizontalPadding: 12,
                action: onDelete
            )
        }
        .frame(width: Self.width)
        .padding(.vertical, 3)
        .glass(cornerRadius: 18, style: .panel)
    }
}
