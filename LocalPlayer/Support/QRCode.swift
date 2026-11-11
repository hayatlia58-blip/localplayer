import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCode {
    /// 生成二维码位图（白底黑码，直接放进页面也看得清）
    static func image(from string: String, scale: CGFloat = 12) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
