import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var cacheCleared = false

    private let rates: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

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

    // MARK: - 绑定

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
