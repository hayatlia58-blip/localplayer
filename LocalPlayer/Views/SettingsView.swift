import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var cacheCleared = false

    private let rates: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    private let colors: [String] = ["#FFFFFF", "#FFE066", "#7ED0FF", "#FFB3C1", "#B8F2C9", "#FFD6A5"]

    var body: some View {
        NavigationStack {
            Form {
                Section("播放") {
                    HStack {
                        Text("默认倍速")
                        Spacer()
                        Picker("", selection: rateBinding) {
                            ForEach(rates, id: \.self) { rate in
                                Text(rateLabel(rate)).tag(rate)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    Toggle("自动连播下一个", isOn: boolBinding(\.autoPlayNext))
                    Toggle("断点续播", isOn: boolBinding(\.resumePlayback))
                    Toggle("自动加载同名字幕", isOn: boolBinding(\.autoSubtitle))
                }

                Section("字幕") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("字号")
                            Spacer()
                            Text("\(Int(settings.subtitleFontSize))")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: doubleBinding(\.subtitleFontSize), in: 14...34, step: 1)
                    }

                    colorRow

                    Toggle("描边（黑边）", isOn: boolBinding(\.subtitleOutline))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("背景不透明度")
                            Spacer()
                            Text("\(Int((settings.subtitleBackgroundOpacity * 100).rounded()))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: doubleBinding(\.subtitleBackgroundOpacity), in: 0...1, step: 0.05)
                    }

                    Toggle("双字幕（需要两份字幕）", isOn: boolBinding(\.dualSubtitle))
                }

                Section("预览") {
                    preview
                }

                Section("存储") {
                    HStack {
                        Text("视频占用")
                        Spacer()
                        Text(Fmt.size(library.totalSize))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("视频数量")
                        Spacer()
                        Text("\(library.allItems.count)")
                            .foregroundColor(.secondary)
                    }
                    Button {
                        ThumbnailLoader.shared.clear()
                        library.reload()
                        cacheCleared = true
                    } label: {
                        HStack {
                            Text("清理缩略图缓存")
                            Spacer()
                            if cacheCleared {
                                Text("已清理")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本地播放器")
                            .font(.system(size: 13, weight: .medium))
                        Text("视频只存在本机 Documents 目录，不联网、不登录、不上传。用「文件」App 可以直接看到这些文件。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 子视图

    private var colorRow: some View {
        HStack(spacing: 12) {
            Text("颜色")
            Spacer()
            ForEach(colors, id: \.self) { hex in
                Button {
                    settings.subtitleColorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(
                                    Color.white.opacity(settings.subtitleColorHex == hex ? 0.95 : 0.18),
                                    lineWidth: settings.subtitleColorHex == hex ? 2 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 6) {
            SubtitleTextView(
                text: "示例字幕：这就是播放时的样子",
                fontSize: settings.subtitleFontSize,
                color: settings.subtitleColor,
                outline: settings.subtitleOutline,
                backgroundOpacity: settings.subtitleBackgroundOpacity
            )

            if settings.dualSubtitle {
                SubtitleTextView(
                    text: "Second subtitle line",
                    fontSize: settings.subtitleFontSize * 0.85,
                    color: settings.subtitleColor,
                    outline: settings.subtitleOutline,
                    backgroundOpacity: settings.subtitleBackgroundOpacity
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    // MARK: - 绑定

    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    private func doubleBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    private var rateBinding: Binding<Double> {
        Binding(
            get: { settings.defaultRate },
            set: { settings.defaultRate = $0 }
        )
    }

    private func rateLabel(_ value: Double) -> String {
        value == 1 ? "1×（正常）" : "\(String(format: "%g", value))×"
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
