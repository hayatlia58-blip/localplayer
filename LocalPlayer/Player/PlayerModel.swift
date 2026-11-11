import AVFoundation
import Combine

/// AVPlayer 封装：时间轴、倍速、缓冲状态
final class PlayerModel: ObservableObject {
    let item: VideoItem
    let player: AVPlayer

    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var rate: Float = 1
    @Published var failed: String?

    var onEnded: (() -> Void)?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    init(item: VideoItem, resumeTime: Double, rate: Float) {
        self.item = item
        let asset = AVURLAsset(url: item.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 5
        player = AVPlayer(playerItem: playerItem)
        player.allowsExternalPlayback = true
        // 常亮交给播放页的「屏幕常亮」开关统一控制
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.rate = rate

        observe(playerItem)
        attachTimeObserver()

        if resumeTime > 5 {
            player.seek(to: CMTime(seconds: resumeTime, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = resumeTime
        }
    }

    // MARK: - 观察

    private func observe(_ playerItem: AVPlayerItem) {
        statusObservation = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if item.status == .failed {
                    self.failed = item.error?.localizedDescription ?? "无法播放该文件"
                }
            }
        }

        durationObservation = playerItem.observe(\.duration, options: [.new]) { [weak self] item, _ in
            let seconds = item.duration.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            DispatchQueue.main.async { self?.duration = seconds }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = true
                    self.isBuffering = true
                default:
                    self.isPlaying = false
                    self.isBuffering = false
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.onEnded?()
        }
    }

    private func attachTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            if seconds.isFinite { self.currentTime = max(0, seconds) }
        }
    }

    // MARK: - 控制

    func play() {
        if player.rate == 0 {
            player.playImmediately(atRate: rate)
        } else {
            player.rate = rate
        }
    }

    func pause() { player.pause() }

    func togglePlay() {
        if isPlaying && player.rate > 0 { pause() } else { play() }
    }

    func seek(to seconds: Double) {
        let clamped = min(max(0, seconds), max(duration - 0.1, 0))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(_ delta: Double) {
        seek(to: currentTime + delta)
    }

    func setRate(_ value: Float) {
        rate = value
        if isPlaying { player.rate = value }
    }

    // MARK: - 清理

    func cleanup() {
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        statusObservation?.invalidate()
        durationObservation?.invalidate()
        timeControlObservation?.invalidate()
        player.replaceCurrentItem(with: nil)
    }
}
