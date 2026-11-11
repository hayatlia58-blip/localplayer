import SwiftUI

// MARK: - 缩略图

struct ThumbnailView: View {
    let item: VideoItem
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Palette.surfaceHigh)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.systemPlayable ? "film" : "exclamationmark.triangle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(Palette.tertiaryText)
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

// MARK: - 进度条（缩略图底部细条）

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

private struct ContainerBadge: View {
    let item: VideoItem

    var body: some View {
        Text(item.ext.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                (item.systemPlayable ? Color.black.opacity(0.55) : Color.orange.opacity(0.9)),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
    }
}

// MARK: - 网格卡片

struct VideoCard: View {
    let item: VideoItem
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ThumbnailView(item: item)
                .overlay(alignment: .bottom) {
                    if fraction > 0.01 {
                        CardProgressBar(fraction: fraction)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    ContainerBadge(item: item).padding(6)
                }

            Text(item.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(Fmt.size(item.fileSize)) · \(Fmt.date.string(from: item.modified))")
                .font(.system(size: 11))
                .foregroundColor(Palette.tertiaryText)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 列表行

struct VideoRow: View {
    let item: VideoItem
    let fraction: Double

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(item: item, cornerRadius: 8)
                .frame(width: 104)
                .overlay(alignment: .bottom) {
                    if fraction > 0.01 {
                        CardProgressBar(fraction: fraction)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(Palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(Fmt.size(item.fileSize)) · \(Fmt.date.string(from: item.modified))")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.tertiaryText)
            }

            Spacer(minLength: 0)

            Text(item.ext.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(item.systemPlayable ? Palette.tertiaryText : .orange)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 继续观看卡片

struct RecentCard: View {
    let item: VideoItem
    let fraction: Double
    let remaining: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(item: item)
                .frame(width: 178)
                .overlay(alignment: .bottom) {
                    if fraction > 0.01 {
                        CardProgressBar(fraction: fraction)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Text("剩余 \(Fmt.time(remaining))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        // 卡片底部有一条 3pt 的进度条，这里要留出空间，否则会贴在一起
                        .padding(.horizontal, 6)
                        .padding(.bottom, 10)
                }

            Text(item.displayName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(Palette.text)
                .lineLimit(1)
        }
        .frame(width: 178, alignment: .leading)
        .contentShape(Rectangle())
    }
}
