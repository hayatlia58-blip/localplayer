import SwiftUI
import AVFoundation

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVVideoGravity
    var onLayer: (AVPlayerLayer) -> Void

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        let layer = view.playerLayer
        DispatchQueue.main.async { onLayer(layer) }
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != gravity {
            uiView.playerLayer.videoGravity = gravity
        }
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }
}
