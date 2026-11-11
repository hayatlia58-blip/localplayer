import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var cacheCleared = false

    private let rates: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 16) {
                        playbackSection
                        storageSection
                        aboutSection
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 头

    private var header: some View {
        HStack {
            Text("设置")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.text)

            Spacer()

            Button("完成") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    // MARK: - 播放

    private var playbackSection: some View {
        card(title: "播放") {
            row {
                Text("默认倍速")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.text)
                Spacer()
                Picker("", selection: rateBinding) {
                    ForEach(rates, id: \.self) { rate in
                        Text(rateLabel(rate)).tag(rate)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Palette.text)
            }

            divider

            VStack(alignment: .leading, spacing: 8) {
                Text("默认播放模式")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.text)

                HStack(spacing: 2) {
                    ForEach(PlayMode.allCases) { mode in
                        let active = settings.defaultPlayMode == mode
                        Button {
                            settings.defaultPlayMode = mode
                        } label: {
                            Text(mode.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(active ? Palette.text : Palette.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background {
                                    if active {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            }
            .padding(.vertical, 4)

            divider

            row {
                VStack(alignment: .leading, spacing: 3) {
                    Text("断点续播")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.text)
                    Text("再次打开时从上次的位置开始")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.tertiaryText)
                }
                Spacer()
                Toggle("", isOn: boolBinding(\.resumePlayback))
                    .labelsHidden()
                    .tint(Palette.accent)
            }
        }
    }

    // MARK: - 存储

    private var storageSection: some View {
        card(title: "存储") {
            row {
                Text("视频占用")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(Fmt.size(library.totalSize))
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondaryText)
                    .monospacedDigit()
            }

            divider

            row {
                Text("视频数量")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("\(library.allItems.count)")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondaryText)
                    .monospacedDigit()
            }

            divider

            Button {
                ThumbnailLoader.shared.clear()
                library.reload()
                cacheCleared = true
            } label: {
                HStack {
                    Text("清理缩略图缓存")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    if cacheCleared {
                        Text("已清理")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 44)
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        card(title: "关于") {
            row {
                Text("版本")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(appVersion)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondaryText)
            }

            divider

            VStack(alignment: .leading, spacing: 6) {
                Text("本地播放器")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text)
                Text("视频只存在本机 Documents 目录，不联网、不登录、不上传。用「文件」App 可以直接看到这些文件。")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 小工具

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.tertiaryText)
                .padding(.bottom, 8)

            VStack(spacing: 0) { content() }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .glass(cornerRadius: 18)
        }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .frame(height: 46)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
    }

    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
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
