import SwiftUI
import AVFoundation
import AVKit
import UIKit

// MARK: - 入口（负责「同目录下一个视频」的切换）

struct PlayerScreen: View {
    let queue: [VideoItem]

    @State private var current: VideoItem
    /// 倍速与模式只在本次播放有效：放在这一层，切集不丢，退出播放页即丢
    @State private var rate: Double
    @State private var mode: PlayMode
    @State private var panel: PlayerPanel?

    @Environment(\.dismiss) private var dismiss

    init(item: VideoItem, queue: [VideoItem]) {
        self.queue = queue
        _current = State(initialValue: item)

        let defaults = UserDefaults.standard
        let savedRate = (defaults.object(forKey: "defaultRate") as? Double) ?? 1.0
        _rate = State(initialValue: savedRate)

        let raw = (defaults.object(forKey: "defaultPlayMode") as? String) ?? PlayMode.loopAll.rawValue
        _mode = State(initialValue: PlayMode(rawValue: raw) ?? .loopAll)
    }

    var body: some View {
        PlayerCore(
            item: current,
            queue: queue,
            rate: $rate,
            mode: $mode,
            panel: $panel,
            onClose: { dismiss() },
            onAdvance: { next in
                if let next {
                    current = next
                } else {
                    dismiss()
                }
            }
        )
        .id(current.id)
        .preferredColorScheme(.dark)
    }
}

// MARK: - 临时状态

private enum DragMode {
    case none, seek, brightness, volume
}

private struct HUD: Equatable {
    var icon: String
    var text: String
    var progress: Double?
}

// MARK: - 播放页主体

private struct PlayerCore: View {
    let item: VideoItem
    let queue: [VideoItem]
    @Binding var rate: Double
    @Binding var mode: PlayMode
    @Binding var panel: PlayerPanel?
    var onClose: () -> Void
    var onAdvance: (VideoItem?) -> Void

    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @StateObject private var model: PlayerModel

    @State private var chromeVisible = true
    @State private var hideToken = 0
    @State private var gravityIndex = 0
    @State private var keepAwake = true
    @State private var toastText: String?

    @State private var hud: HUD?
    @State private var hudToken = 0

    @State private var dragMode: DragMode = .none
    @State private var dragStartTime: Double = 0
    @State private var seekTarget: Double = 0
    @State private var brightnessStart: CGFloat = 0
    @State private var volumeStart: Float = 0

    @State private var boosting = false
    @State private var scrubFraction: Double?
    @State private var isScrubbing = false

    @State private var pendingResume: Double = 0
    @State private var didRestore = false
    @State private var lastSavedAt: Double = 0

    init(
        item: VideoItem,
        queue: [VideoItem],
        rate: Binding<Double>,
        mode: Binding<PlayMode>,
        panel: Binding<PlayerPanel?>,
        onClose: @escaping () -> Void,
        onAdvance: @escaping (VideoItem?) -> Void
    ) {
        self.item = item
        self.queue = queue
        _rate = rate
        _mode = mode
        _panel = panel
        self.onClose = onClose
        self.onAdvance = onAdvance
        _model = StateObject(wrappedValue: PlayerModel(item: item, resumeTime: 0, rate: 1))
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var showControls: Bool { chromeVisible && panel == nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                VideoSurface(player: model.player, gravity: gravity) { _ in }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(size: geo.size))
                    .highPriorityGesture(doubleTapGesture(size: geo.size))
                    .onTapGesture { handleTap() }
                    .onLongPressGesture(
                        minimumDuration: 0.35,
                        maximumDistance: 60,
                        perform: { startBoost() },
                        onPressingChanged: { pressing in
                            if !pressing { endBoost() }
                        }
                    )
                    .simultaneousGesture(magnifyGesture)
            }
            .ignoresSafeArea()

            if panel != nil {
                // 抽屉展开时整层控件收起，画面与抽屉互不遮挡
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { closePanel() }
                    .transition(.opacity)
            }

            if showControls {
                controlsLayer
                    .transition(.opacity)
            }

            hudLayer

            if let toastText {
                toastView(toastText)
            }

            if let failed = model.failed {
                errorLayer(failed)
            }
        }
        .overlay(alignment: .trailing) { panelLayer }
        .background(Color.black)
        .onAppear { setup() }
        .onDisappear { teardown() }
        .onChange(of: rate) { _, value in
            model.setRate(Float(value))
        }
        .onChange(of: keepAwake) { _, value in
            UIApplication.shared.isIdleTimerDisabled = value
        }
        .onChange(of: model.duration) { _, value in
            if !didRestore, value > 0 { restorePosition() }
        }
        .onChange(of: model.isPlaying) { _, playing in
            if playing {
                scheduleHide()
            } else {
                showChrome(persistent: true)
            }
        }
        .onChange(of: model.currentTime) { _, _ in
            maybeSaveProgress()
        }
    }

    private var gravity: AVLayerVideoGravity {
        switch gravityIndex {
        case 1: return .resizeAspectFill
        case 2: return .resize
        default: return .resizeAspect
        }
    }

    // MARK: - 手势

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in handleDragChanged(value, size: size) }
            .onEnded { _ in handleDragEnded() }
    }

    private func doubleTapGesture(size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                showChrome(persistent: false)
                if value.location.x < size.width * 0.35 {
                    model.skip(-10)
                    flashHUD(HUD(icon: "gobackward.10", text: "-10 秒", progress: nil), duration: 0.8)
                } else if value.location.x > size.width * 0.65 {
                    model.skip(10)
                    flashHUD(HUD(icon: "goforward.10", text: "+10 秒", progress: nil), duration: 0.8)
                } else {
                    model.togglePlay()
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onEnded { value in
                if value.magnification > 1.05 {
                    gravityIndex = 1
                } else if value.magnification < 0.95 {
                    gravityIndex = 0
                }
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
        if dragMode == .none {
            let dx = abs(value.translation.width)
            let dy = abs(value.translation.height)
            guard max(dx, dy) > 6 else { return }

            if dx > dy {
                dragMode = .seek
                dragStartTime = model.currentTime
                seekTarget = model.currentTime
                showChrome(persistent: false)
            } else if value.startLocation.x < size.width / 2 {
                dragMode = .brightness
                brightnessStart = ScreenBrightness.current
            } else {
                dragMode = .volume
                volumeStart = SystemVolume.shared.value
            }
        }

        switch dragMode {
        case .seek:
            let span = min(max(model.duration * 0.4, 60), 240)
            let ratio = Double(value.translation.width / max(size.width, 1))
            let target = min(max(0, dragStartTime + ratio * span), max(model.duration - 0.5, 0))
            seekTarget = target
            hud = HUD(
                icon: "timeline.selection",
                text: "\(Fmt.time(target)) / \(Fmt.time(model.duration))",
                progress: model.duration > 0 ? target / model.duration : nil
            )

        case .brightness:
            let delta = -value.translation.height / max(size.height * 0.6, 1)
            let next = min(max(brightnessStart + delta, 0), 1)
            ScreenBrightness.set(next)
            hud = HUD(
                icon: "sun.max.fill",
                text: "\(Int((Double(next) * 100).rounded()))%",
                progress: Double(next)
            )

        case .volume:
            let delta = Float(-value.translation.height / max(size.height * 0.6, 1))
            let next = min(max(volumeStart + delta, 0), 1)
            SystemVolume.shared.set(next)
            hud = HUD(
                icon: next > 0.01 ? "speaker.wave.2.fill" : "speaker.slash.fill",
                text: "\(Int((next * 100).rounded()))%",
                progress: Double(next)
            )

        case .none:
            break
        }
    }

    private func handleDragEnded() {
        if dragMode == .seek {
            model.seek(to: seekTarget)
        }
        dragMode = .none
        fadeHUD(after: 0.6)
    }

    private func startBoost() {
        guard model.isPlaying, panel == nil else { return }
        boosting = true
        model.setRate(2)
        flashHUD(HUD(icon: "forward.fill", text: "2× 快进", progress: nil), duration: 6)
    }

    private func endBoost() {
        guard boosting else { return }
        boosting = false
        model.setRate(Float(rate))
        hud = nil
    }

    private func handleTap() {
        if panel != nil {
            closePanel()
        } else {
            toggleChrome()
        }
    }

    // MARK: - HUD / 显隐

    private func flashHUD(_ value: HUD, duration: Double = 0.9) {
        hudToken += 1
        hud = value
        fadeHUD(after: duration)
    }

    private func fadeHUD(after delay: Double) {
        let token = hudToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if hudToken == token {
                withAnimation(.easeOut(duration: 0.2)) { hud = nil }
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { toastText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeIn(duration: 0.2)) { toastText = nil }
        }
    }

    private func toggleChrome() {
        if chromeVisible {
            hideToken += 1
            withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = false }
        } else {
            showChrome(persistent: false)
        }
    }

    private func showChrome(persistent: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = true }
        hideToken += 1
        if persistent { return }
        scheduleHide()
    }

    private func scheduleHide() {
        #if DEBUG
        if DebugSeed.argument(after: "-keepChrome") == "1" { return }
        #endif
        hideToken += 1
        let token = hideToken
        guard model.isPlaying, panel == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if hideToken == token, model.isPlaying {
                withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = false }
            }
        }
    }

    private func openPanel(_ target: PlayerPanel) {
        hideToken += 1
        withAnimation(.easeOut(duration: 0.22)) {
            panel = (panel == target) ? nil : target
            chromeVisible = false
        }
    }

    private func closePanel() {
        withAnimation(.easeOut(duration: 0.2)) { panel = nil }
        showChrome(persistent: false)
    }

    // MARK: - 控制层

    private var controlsLayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                GlassIconButton(
                    systemName: "xmark",
                    size: 38,
                    iconSize: 15,
                    weight: .semibold,
                    style: .panel
                ) { onClose() }

                Spacer(minLength: 0)

                GlassIconButton(
                    systemName: "camera",
                    size: 38,
                    iconSize: 15,
                    weight: .semibold,
                    style: .panel
                ) { grabFrame() }
            }
            .padding(.horizontal, isLandscape ? 16 : 20)
            .padding(.top, isLandscape ? 14 : 8)

            Spacer(minLength: 0)

            bottomBar
        }
    }

    private var bottomBar: some View {
        Group {
            if isLandscape {
                HStack(spacing: 12) {
                    transportPill
                    progressPill
                    panelButton(.queue, icon: "list.bullet")
                    panelButton(.settings, icon: "slider.horizontal.3")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                VStack(spacing: 12) {
                    VStack(spacing: 7) {
                        scrubBar
                        timesRow
                    }

                    HStack(spacing: 12) {
                        transportPill
                        Spacer(minLength: 8)
                        panelButton(.queue, icon: "list.bullet")
                        panelButton(.settings, icon: "slider.horizontal.3")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 38)
            }
        }
    }

    private var transportPill: some View {
        HStack(spacing: 0) {
            pillButton("gobackward.10") {
                model.skip(-10)
                flashHUD(HUD(icon: "gobackward.10", text: "-10 秒", progress: nil), duration: 0.8)
            }
            pillButton(model.isPlaying ? "pause.fill" : "play.fill", width: 56) {
                model.togglePlay()
            }
            pillButton("goforward.10") {
                model.skip(10)
                flashHUD(HUD(icon: "goforward.10", text: "+10 秒", progress: nil), duration: 0.8)
            }
        }
        .frame(height: 50)
        .glass(Capsule())
    }

    private func pillButton(_ icon: String, width: CGFloat = 46, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: width, height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var progressPill: some View {
        VStack(spacing: 7) {
            scrubBar
            timesRow
        }
        .padding(.horizontal, 15)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .glass(Capsule())
    }

    private func panelButton(_ target: PlayerPanel, icon: String) -> some View {
        Button {
            openPanel(target)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(Circle())
    }

    private var displayTime: Double {
        if isScrubbing, let scrubFraction {
            return scrubFraction * max(model.duration, 0)
        }
        return model.currentTime
    }

    private var playFraction: Double {
        let played = model.duration > 0 ? model.currentTime / model.duration : 0
        return min(max(isScrubbing ? (scrubFraction ?? played) : played, 0), 1)
    }

    private var scrubBar: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.white)
                    .frame(width: width * CGFloat(playFraction), height: 4)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        scrubFraction = Double(min(max(value.location.x / width, 0), 1))
                    }
                    .onEnded { value in
                        let x = min(max(value.location.x / width, 0), 1)
                        model.seek(to: Double(x) * model.duration)
                        isScrubbing = false
                        scrubFraction = nil
                    }
            )
        }
        .frame(height: 20)
    }

    private var timesRow: some View {
        HStack(spacing: 8) {
            Text(Fmt.time(displayTime))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.90))

            Spacer(minLength: 0)

            Text("-\(Fmt.time(max(0, model.duration - displayTime)))")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - 抽屉

    @ViewBuilder
    private var panelLayer: some View {
        if let panel {
            Group {
                switch panel {
                case .queue:
                    QueuePanel(queue: queue, current: item, isLandscape: isLandscape) { next in
                        if next.id == item.id {
                            closePanel()
                        } else {
                            onAdvance(next)
                        }
                    }
                case .settings:
                    SettingsPanel(
                        isLandscape: isLandscape,
                        rate: $rate,
                        mode: $mode,
                        gravityIndex: $gravityIndex,
                        keepAwake: $keepAwake
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.vertical, isLandscape ? 0 : 4)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    // MARK: - 浮层

    private func toastView(_ text: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glass(Capsule())
                .padding(.bottom, 120)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    @ViewBuilder
    private var hudLayer: some View {
        if let hud {
            VStack(spacing: 9) {
                Image(systemName: hud.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)

                Text(hud.text)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                if let value = hud.progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.25))
                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(0, geo.size.width * CGFloat(min(max(value, 0), 1))))
                        }
                    }
                    .frame(width: 120, height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Color.black.opacity(0.58),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func errorLayer(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.85))

            Text("无法播放")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)

            if !item.systemPlayable {
                Text("\(item.ext.uppercased()) 容器系统播放器不支持，需要转成 mp4 / mov。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button(action: onClose) {
                Text("关闭")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 36)
                    .glass(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 330)
        .glass(cornerRadius: 18)
    }

    // MARK: - 生命周期

    private func setup() {
        model.onEnded = { handleEnded() }
        model.setRate(Float(rate))
        pendingResume = settings.resumePlayback ? progress.position(for: item.id) : 0

        model.play()
        UIApplication.shared.isIdleTimerDisabled = keepAwake
        showChrome(persistent: false)
        #if DEBUG
        DebugSeed.forceLandscapeIfRequested()
        #endif
    }

    private func restorePosition() {
        didRestore = true
        guard pendingResume > 5 else { return }
        model.seek(to: pendingResume)
        flashHUD(
            HUD(icon: "arrow.uturn.backward", text: "从 \(Fmt.time(pendingResume)) 继续", progress: nil),
            duration: 1.6
        )
    }

    private func maybeSaveProgress() {
        guard model.duration > 1, model.isPlaying else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastSavedAt > 4 else { return }
        lastSavedAt = now
        progress.update(id: item.id, time: model.currentTime, total: model.duration)
    }

    private func teardown() {
        if model.duration > 1 {
            progress.update(id: item.id, time: model.currentTime, total: model.duration)
        }
        UIApplication.shared.isIdleTimerDisabled = false
        model.cleanup()
    }

    private func handleEnded() {
        progress.clear(id: item.id)

        switch mode {
        case .loopOne:
            model.seek(to: 0)
            model.play()

        case .loopAll:
            if let next = nextItem(wrapping: true), next.id != item.id {
                onAdvance(next)
            } else {
                model.seek(to: 0)
                model.play()
            }

        case .stopAtEnd:
            model.pause()
            showChrome(persistent: true)
        }
    }

    private func nextItem(wrapping: Bool) -> VideoItem? {
        guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return nil }
        let next = index + 1
        if next < queue.count { return queue[next] }
        return wrapping ? queue.first : nil
    }

    // MARK: - 截图

    private func grabFrame() {
        FrameGrabber.capture(url: item.url, at: model.currentTime) { result in
            switch result {
            case .success:
                showToast("已存到相册")
            case .failure(let error):
                showToast(error.localizedDescription)
            }
        }
    }
}
