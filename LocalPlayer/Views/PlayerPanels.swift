import SwiftUI

enum PlayerPanel: Equatable {
    case queue
    case settings
}

// MARK: - 抽屉外壳

struct PanelShell<Content: View>: View {
    let isLandscape: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let width: CGFloat = isLandscape ? 320 : 264

        Group {
            if isLandscape {
                ScrollView(showsIndicators: false) {
                    content.padding(18)
                }
                .frame(width: width)
                .frame(maxHeight: .infinity)
            } else {
                // 竖屏：高度按内容算，不硬拉到屏幕底
                content.padding(16)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .glass(cornerRadius: 28, style: .panel)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
    }
}

// MARK: - 分组标题 / 分隔

private struct PanelGroupTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Palette.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

private struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
    }
}

// MARK: - 播放列表抽屉

struct QueuePanel: View {
    let queue: [VideoItem]
    let current: VideoItem
    let isLandscape: Bool
    var onSelect: (VideoItem) -> Void

    @State private var durations: [String: Double] = [:]

    private var index: Int {
        (queue.firstIndex { $0.id == current.id } ?? 0) + 1
    }

    var body: some View {
        PanelShell(isLandscape: isLandscape) {
            VStack(alignment: .leading, spacing: 0) {
                Text("正在播放")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.tertiaryText)

                Text(current.displayName)
                    .font(.system(size: isLandscape ? 18 : 22, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .padding(.top, 6)

                Text(subLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                    .monospacedDigit()
                    .padding(.top, 4)

                Text("第 \(index) 个 · 共 \(queue.count) 个")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.tertiaryText)
                    .monospacedDigit()
                    .padding(.top, 2)

                PanelDivider().padding(.vertical, 12)

                VStack(spacing: 0) {
                    ForEach(queue) { item in
                        row(item)
                    }
                }
            }
        }
        .task(id: current.id) { await loadDurations() }
    }

    private var subLine: String {
        var parts: [String] = []
        if let duration = durations[current.id] {
            parts.append(Fmt.time(duration))
        }
        parts.append(Fmt.size(current.fileSize))
        return parts.joined(separator: " · ")
    }

    private func row(_ item: VideoItem) -> some View {
        let isCurrent = item.id == current.id
        return Button {
            onSelect(item)
        } label: {
            HStack(spacing: 10) {
                ThumbnailView(item: item, cornerRadius: 6)
                    .frame(width: isLandscape ? 60 : 80)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Palette.accent, lineWidth: 2)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Palette.text : Palette.text.opacity(0.86))
                        .lineLimit(1)

                    Text(durationText(item))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryText)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)

                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(.vertical, isLandscape ? 4 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func durationText(_ item: VideoItem) -> String {
        if let value = durations[item.id] { return Fmt.time(value) }
        return Fmt.size(item.fileSize)
    }

    private func loadDurations() async {
        for item in queue where durations[item.id] == nil {
            if let value = await ThumbnailLoader.shared.duration(for: item) {
                durations[item.id] = value
            }
        }
    }
}

// MARK: - 播放设置抽屉

struct SettingsPanel: View {
    let isLandscape: Bool
    @Binding var rate: Double
    @Binding var mode: PlayMode
    @Binding var gravityIndex: Int
    @Binding var keepAwake: Bool

    private let rates: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    private let gravityTitles = ["适应", "填充", "拉伸"]

    var body: some View {
        PanelShell(isLandscape: isLandscape) {
            VStack(alignment: .leading, spacing: 0) {
                Text("播放设置")
                    .font(.system(size: isLandscape ? 16 : 18, weight: .semibold))
                    .foregroundStyle(Palette.text)

                PanelGroupTitle(text: "播放")

                HStack(spacing: 10) {
                    Text("倍速")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.text)

                    Spacer(minLength: 0)

                    stepButton("minus") { step(-0.25) }

                    Text(rateText)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                        .frame(width: 48)

                    stepButton("plus") { step(0.25) }
                }
                .frame(height: rowHeight)

                PanelDivider().padding(.vertical, 6)

                Text("模式")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.text)
                    .frame(height: rowHeight, alignment: .leading)

                SegmentedBar(
                    titles: PlayMode.allCases.map(\.title),
                    selected: PlayMode.allCases.firstIndex(of: mode) ?? 0
                ) { index in
                    mode = PlayMode.allCases[index]
                }

                PanelGroupTitle(text: "画面")

                SegmentedBar(titles: gravityTitles, selected: gravityIndex) { index in
                    gravityIndex = index
                }

                PanelGroupTitle(text: "界面")

                HStack(spacing: 10) {
                    Text("屏幕常亮")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.text)
                    Spacer(minLength: 0)
                    Toggle("", isOn: $keepAwake)
                        .labelsHidden()
                        .tint(Palette.accent)
                }
                .frame(height: rowHeight)

                PanelDivider().padding(.vertical, 10)

                Text("倍速与模式只在本次播放有效，退出播放页就恢复默认")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rowHeight: CGFloat { isLandscape ? 38 : 42 }

    private var rateText: String {
        rate == 1 ? "1×" : "\(String(format: "%g", rate))×"
    }

    private func step(_ delta: Double) {
        let next = ((rate + delta) * 4).rounded() / 4
        rate = min(max(next, 0.5), 2)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 三段选择

private struct SegmentedBar: View {
    let titles: [String]
    let selected: Int
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(titles.indices, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Text(titles[index])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected == index ? Palette.text : Palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background {
                            if selected == index {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Color.white.opacity(0.16))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
