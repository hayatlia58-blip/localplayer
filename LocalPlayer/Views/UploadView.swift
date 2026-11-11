import SwiftUI
import UIKit

/// Wi-Fi 传文件：开一个局域网 HTTP 服务，电脑浏览器拖拽上传
struct UploadView: View {
    @StateObject private var server = WiFiUploadServer()
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var copied = false
    @State private var qrImage: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        addressCard
                        qrCard
                        statusRow
                        tips
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Wi-Fi 传文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            server.onUpload = { _ in
                library.reload()
            }
            server.start()
        }
        .onChange(of: server.addressText) { _, text in
            qrImage = QRCode.image(from: text)
        }
        .onDisappear {
            server.stop()
        }
    }

    private var addressCard: some View {
        VStack(spacing: 10) {
            Text("在电脑浏览器里打开这个地址")
                .font(.system(size: 12))
                .foregroundColor(Palette.secondaryText)

            Button {
                UIPasteboard.general.string = server.addressText
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            } label: {
                HStack(spacing: 10) {
                    Text(server.addressText.isEmpty ? "正在启动…" : server.addressText)
                        .font(.system(size: 19, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(copied ? Color.green : Palette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(server.addressText.isEmpty)

            Text("手机和电脑要连同一个 Wi-Fi，地址才对得上")
                .font(.system(size: 11.5))
                .foregroundColor(Palette.tertiaryText)
        }
    }

    private var qrCard: some View {
        VStack(spacing: 10) {
            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.surface)
                    .frame(width: 174, height: 174)
                    .overlay(
                        Image(systemName: "qrcode")
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(Palette.tertiaryText)
                    )
            }

            Text("扫码也能直接进上传页")
                .font(.system(size: 11.5))
                .foregroundColor(Palette.tertiaryText)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(server.isRunning ? Color.green : Color.orange)
                .frame(width: 7, height: 7)

            Text(server.isRunning ? "服务已开启" : "服务未启动")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(Palette.text)

            Spacer(minLength: 0)

            Text("本次已接收 \(server.receivedCount) 个")
                .font(.system(size: 12))
                .foregroundColor(Palette.secondaryText)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            tip("拖拽或点击选择文件，可多选，顺序上传")
            tip("大文件建议用网线或 5GHz Wi-Fi，2.4G 会慢")
            tip("传输期间请保持这个页面打开")
            tip("关掉页面即停止服务，不会在后台跑")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Palette.tertiaryText)
                .frame(width: 3, height: 3)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
