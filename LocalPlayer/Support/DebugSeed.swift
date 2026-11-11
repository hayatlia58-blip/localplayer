#if DEBUG
import AVFoundation
import CoreVideo
import UIKit

/// 仅 Debug 编译。用于在模拟器里生成几段示例视频，
/// 这样启动后能看到真实的缩略图/卡片/续播，而不是空列表。
/// 通过启动参数 `-seedDemo 1` 触发，正式包不包含这些代码。
enum DebugSeed {

    /// 启动参数里 `flag` 后面跟的值，例如 `-screen player`
    static func argument(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var isEnabled: Bool { argument(after: "-seedDemo") == "1" }

    static func runIfNeeded() {
        guard isEnabled else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("示例视频", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard existing.isEmpty else { return }

        let specs: [(name: String, top: UIColor, bottom: UIColor)] = [
            ("海边的日落.mp4", UIColor(red: 0.98, green: 0.55, blue: 0.35, alpha: 1),
                              UIColor(red: 0.18, green: 0.16, blue: 0.42, alpha: 1)),
            ("城市夜景 4K.mp4", UIColor(red: 0.10, green: 0.14, blue: 0.32, alpha: 1),
                               UIColor(red: 0.36, green: 0.10, blue: 0.42, alpha: 1)),
            ("雪山航拍.mp4", UIColor(red: 0.55, green: 0.72, blue: 0.92, alpha: 1),
                            UIColor(red: 0.94, green: 0.96, blue: 0.99, alpha: 1)),
            ("老电影片段.mov", UIColor(red: 0.32, green: 0.26, blue: 0.18, alpha: 1),
                              UIColor(red: 0.62, green: 0.52, blue: 0.36, alpha: 1))
        ]

        for spec in specs {
            writeClip(to: folder.appendingPathComponent(spec.name),
                      top: spec.top, bottom: spec.bottom, seconds: 8)
        }

        // 给第一个视频配一条外挂字幕，顺便验证字幕解析链路
        let srt = """
        1
        00:00:00,000 --> 00:00:03,000
        这是一行测试字幕，用来检查字号和描边

        2
        00:00:03,000 --> 00:00:07,000
        第二句：English subtitle for layout check

        """
        try? srt.write(to: folder.appendingPathComponent("海边的日落.srt"),
                       atomically: true, encoding: .utf8)
    }

    // MARK: - 生成一段纯色渐变的 mp4

    private static func writeClip(to url: URL, top: UIColor, bottom: UIColor, seconds: Int) {
        try? FileManager.default.removeItem(at: url)

        let width = 640, height = 360
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: url.pathExtension == "mov" ? .mov : .mp4) else { return }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(input) else { return }
        writer.add(input)
        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 4
        let frames = seconds * Int(fps)

        for index in 0..<frames {
            while !input.isReadyForMoreMediaData { usleep(2000) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
                  let pixelBuffer = buffer else { break }

            draw(pixelBuffer, top: top, bottom: bottom, progress: CGFloat(index) / CGFloat(max(frames - 1, 1)))
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: fps))
        }

        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        _ = done.wait(timeout: .now() + 15)
    }

    private static func draw(_ buffer: CVPixelBuffer, top: UIColor, bottom: UIColor, progress: CGFloat) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return }

        // 竖向渐变
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [top.cgColor, bottom.cgColor] as CFArray,
                                     locations: [0, 1]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: height),
                                       end: CGPoint(x: 0, y: 0),
                                       options: [])
        }

        // 一个缓慢右移的圆，让缩略图之间能明显区分
        context.setFillColor(UIColor(white: 1, alpha: 0.22).cgColor)
        let radius = CGFloat(height) * 0.22
        let x = radius + (CGFloat(width) - radius * 2) * progress
        context.fillEllipse(in: CGRect(x: x - radius, y: CGFloat(height) * 0.42 - radius,
                                       width: radius * 2, height: radius * 2))

        // 地平线
        context.setFillColor(UIColor(white: 0, alpha: 0.28).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height) * 0.30))
    }
}
#endif
