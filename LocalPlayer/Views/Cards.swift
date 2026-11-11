import SwiftUI

// MARK: - 缩略图

struct ThumbnailView: View {
    let item: VideoItem
    var cornerRadius: CGFloat = 12

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color(white: 0.09))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.systemPlayable ? "film" : "exclamationmark.triangle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            ThumbnailLoader.shared.load(for: item, size: CGSize(width: 480, height: 270)) { loaded in
                image = loaded
            }
        }
    }
}

// MARK: - 缩略图底部细进度条

private struct CardProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.22))
                Rectangle()
                    .fill(Palette.accent)
                    .frame(width: max(0, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 3)
    }
}

// MARK: - 右下角已看角标

struct WatchedBadge: View {
    var active: Bool

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(active ? Color(red: 0.08, green: 0.09, blue: 0.10) : Color.white)
            .frame(width: 22, height: 22)
            .background {
                Circle()
                    .fill(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(Material.ultraThinMaterial))
                    .overlay {
                        Circle().fill(active ? Color.clear : Color.black.opacity(0.34))
                    }
                    .overlay {
                        Circle().strokeBorder(
                            Color.white.opacity(active ? 0 : 0.42),
                            lineWidth: 0.75
                        )
                    }
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
            }
    }
}

// MARK: - 网格卡片

struct VideoCard: View {
    let item: VideoItem
    let fraction: Double
    var watched: Bool = false
    /// 长按选中时角标变实心白底
    var active: Bool = false

    @State private var duration: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThumbnailView(item: item)
                .overlay(alignment: .bottom) {
                    if fraction > 0.01, !watched {
                        CardProgressBar(fraction: fraction)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if watched || active {
                        WatchedBadge(active: active)
                            .padding(8)
                    }
                }

            Text(item.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 9)

            Text(metaText)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .task(id: item.id) {
            duration = await ThumbnailLoader.shared.duration(for: item)
        }
    }

    private var metaText: String {
        if let duration, duration > 0 {
            return "\(Fmt.time(duration)) · \(Fmt.size(item.fileSize))"
        }
        return Fmt.size(item.fileSize)
    }
}

// MARK: - 文件夹卡片

struct FolderCard: View {
    let name: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                Image(systemName: "folder.fill")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Palette.accent.opacity(0.9))
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)

            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .padding(.top, 9)

            Text("\(count) 个视频")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.secondaryText)
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
    }
}
