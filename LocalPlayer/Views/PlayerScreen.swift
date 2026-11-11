import SwiftUI
import AVFoundation
import AVKit
import UIKit

// MARK: - 入口（负责「同目录下一个视频」的切换）

struct PlayerScreen: View {
    let queue: [VideoItem]
    @State private var current: VideoItem
    @Environment(\.dismiss) private var dismiss

    init(item: VideoItem, queue: [VideoItem]) {
        self.queue = queue
        _current = State(initialValue: item)
    }

    var body: some View {
        PlayerCore(
            item: current,
            queue: queue,
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
    var onClose: () -> Void
    var onAdvance: (VideoItem?) -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @StateObject private var model: PlayerModel
    @StateObject private var pip = PiPManager()

    @State private var gravity: AVLayerVideoGravity = .resizeAspect
    @State private var chromeVisible = true
    @State private var hideToken = 0

    @State private var hud: HUD?
    @State private var hudToken = 0

    @State private var dragMode: DragMode = .none
    @State private var dragStartTime: Double = 0
    @State private var seekTarget: Double = 0
    @State private var brightnessStart: CGFloat = 0
    @State private var volumeStart: Float = 0

    @State private var boosting = false
    @State private var scrubFraction: Double?

    @State private var showSubtitleImporter = false
    @State private var subtitleImportSecondary = false

    @State private var pendingResume: Double = 0
    @State private var didRestore = false
    @State private var lastSavedAt: Double = 0
    @State private var subtitles: [URL] = []

    init(
        item: VideoItem,
        queue: [VideoItem],
        onClose: @escaping () -> Void,
        onAdvance: @escaping (VideoItem?) -> Void
    ) {
        self.item = item
        self.queue = queue
        self.onClose = onClose
        self.onAdvance = onAdvance
        _model = StateObject(wrappedValue: PlayerModel(item: item, resumeTime: 0, rate: 1))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                VideoSurface(player: model.player, gravity: gravity) { layer in
                    pip.attach(layer: layer)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(dragGesture(size: geo.size))
                .highPriorityGesture(doubleTapGesture(size: geo.size))
                .onTapGesture { toggleChrome() }
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

            // 顺序有讲究：控制层在下、字幕和 HUD 在上，
            // 否则控制层顶部/底部的黑色渐变会把字幕压暗
            if chromeVisible {
                controlsLayer
                    .transition(.opacity)
            }

            hudLayer
            subtitleLayer

            if let failed = model.failed {
                errorLayer(failed)
            }
        }
        .background(Color.black)
        .onAppear { setup() }
        .onDisappear { teardown() }
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
        .fileImporter(
            isPresented: $showSubtitleImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleSubtitleImport(result)
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
                    gravity = .resizeAspectFill
                } else if value.magnification < 0.95 {
                    gravity = .resizeAspect
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
            // 整块屏幕宽度对应多少秒：短片温柔些，长片跨度大些
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
        guard model.isPlaying else { return }
        boosting = true
        model.setRate(max(2, Float(settings.defaultRate)))
        flashHUD(HUD(icon: "forward.fill", text: "2× 快进", progress: nil), duration: 6)
    }

    private func endBoost() {
        guard boosting else { return }
        boosting = false
        model.setRate(Float(settings.defaultRate))
        hud = nil
    }

    // MARK: - HUD / 控制层显隐

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
        // 自动化截图用：把控制栏钉住，避免 4 秒自动隐藏导致拍不到
        if DebugSeed.argument(after: "-keepChrome") == "1" { return }
        #endif
        hideToken += 1
        let token = hideToken
        guard model.isPlaying else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if hideToken == token, model.isPlaying {
                withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = false }
            }
        }
    }

    // MARK: - 控制层

    private var controlsLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.04),
                    Color.black.opacity(0.62)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                centerButtons
                Spacer(minLength: 8)
                bottomBar
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.35), in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(subtitleLine)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if pip.isSupported {
                roundIcon("pip.enter") { pip.toggle() }
            }
            subtitleMenu
            moreMenu
        }
    }

    private var subtitleLine: String {
        var parts: [String] = [item.ext.uppercased()]
        if !item.folder.isEmpty {
            parts.append((item.folder as NSString).lastPathComponent)
        }
        if let name = model.primarySubtitleName {
            let base = (name as NSString).deletingPathExtension
            // 外挂字幕常与视频同名，同名时不要重复显示标题
            parts.append(base == item.displayName ? "外挂字幕" : "字幕 \(base)")
        }
        return parts.joined(separator: " · ")
    }

    private func roundIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.35), in: Circle())
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Button {
                model.clearPrimarySubtitle()
                model.clearSecondarySubtitle()
                model.selectLegible(-1)
                flashHUD(HUD(icon: "captions.bubble", text: "字幕已关闭", progress: nil))
            } label: {
                Label("关闭字幕", systemImage: "captions.bubble")
            }

            if !model.legibleOptions.isEmpty {
                Menu("内嵌字幕") {
                    ForEach(model.legibleOptions.indices, id: \.self) { index in
                        Button {
                            model.clearPrimarySubtitle()
                            model.selectLegible(index)
                        } label: {
                            if model.selectedLegibleIndex == index {
                                Label(trackName(model.legibleOptions[index], index: index), systemImage: "checkmark")
                            } else {
                                Text(trackName(model.legibleOptions[index], index: index))
                            }
                        }
                    }
                }
            }

            if !subtitles.isEmpty {
                Menu("外挂字幕") {
                    ForEach(subtitles.indices, id: \.self) { index in
                        Button(subtitles[index].lastPathComponent) {
                            model.loadPrimarySubtitle(subtitles[index])
                        }
                    }
                }
            }

            Divider()

            Button {
                subtitleImportSecondary = false
                showSubtitleImporter = true
            } label: {
                Label("导入字幕文件…", systemImage: "plus.circle")
            }

            if settings.dualSubtitle {
                Button {
                    subtitleImportSecondary = true
                    showSubtitleImporter = true
                } label: {
                    Label("导入副字幕文件…", systemImage: "plus.circle")
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.35), in: Circle())
        }
    }

    private var moreMenu: some View {
        Menu {
            Menu("画面比例") {
                Button {
                    gravity = .resizeAspect
                } label: {
                    if gravity == .resizeAspect {
                        Label("适应屏幕", systemImage: "checkmark")
                    } else {
                        Text("适应屏幕")
                    }
                }
                Button {
                    gravity = .resizeAspectFill
                } label: {
                    if gravity == .resizeAspectFill {
                        Label("填充屏幕", systemImage: "checkmark")
                    } else {
                        Text("填充屏幕")
                    }
                }
                Button {
                    gravity = .resize
                } label: {
                    if gravity == .resize {
                        Label("拉伸铺满", systemImage: "checkmark")
                    } else {
                        Text("拉伸铺满")
                    }
                }
            }

            if !model.audioOptions.isEmpty {
                Menu("音轨") {
                    ForEach(model.audioOptions.indices, id: \.self) { index in
                        Button {
                            model.selectAudio(index)
                        } label: {
                            if model.selectedAudioIndex == index {
                                Label(trackName(model.audioOptions[index], index: index), systemImage: "checkmark")
                            } else {
                                Text(trackName(model.audioOptions[index], index: index))
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                progress.clear(id: item.id)
                model.seek(to: 0)
                flashHUD(HUD(icon: "arrow.counterclockwise", text: "已从头开始", progress: nil))
            } label: {
                Label("从头播放", systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.35), in: Circle())
        }
    }

    private func trackName(_ option: AVMediaSelectionOption, index: Int) -> String {
        let name = option.displayName
        return name.isEmpty ? "轨道 \(index + 1)" : name
    }

    private var centerButtons: some View {
        HStack(spacing: 44) {
            Button {
                model.skip(-10)
                flashHUD(HUD(icon: "gobackward.10", text: "-10 秒", progress: nil), duration: 0.8)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.black.opacity(0.3), in: Circle())
            }

            Button {
                if model.isPlaying {
                    model.pause()
                } else {
                    model.play()
                }
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.black.opacity(0.4), in: Circle())
            }

            Button {
                model.skip(10)
                flashHUD(HUD(icon: "goforward.10", text: "+10 秒", progress: nil), duration: 0.8)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.black.opacity(0.3), in: Circle())
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(Fmt.time(displayTime))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 50, alignment: .leading)

                progressBar

                Text(Fmt.time(model.duration))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 50, alignment: .trailing)
            }

            HStack(spacing: 12) {
                rateMenu
                if boosting {
                    Text("2× 快进中")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Palette.accent)
                }
                Spacer(minLength: 0)
                if model.duration > 1 {
                    Text("−\(Fmt.time(max(0, model.duration - displayTime)))")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.45))
                }
            }
        }
    }

    private var displayTime: Double {
        if let scrubFraction {
            return scrubFraction * max(model.duration, 0)
        }
        return model.currentTime
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let played = model.duration > 0 ? model.currentTime / model.duration : 0
            let fraction = min(max(scrubFraction ?? played, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(height: 4)

                Capsule()
                    .fill(Palette.accent)
                    .frame(width: width * CGFloat(fraction), height: 4)

                Circle()
                    .fill(Color.white)
                    .frame(width: 11, height: 11)
                    .offset(x: width * CGFloat(fraction) - 5.5)
                    .opacity(scrubFraction == nil ? 0.9 : 1)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x / width, 0), 1)
                        scrubFraction = Double(x)
                    }
                    .onEnded { value in
                        let x = min(max(value.location.x / width, 0), 1)
                        model.seek(to: Double(x) * model.duration)
                        scrubFraction = nil
                    }
            )
        }
        .frame(height: 22)
    }

    private var rateMenu: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { value in
                Button {
                    model.setRate(Float(value))
                } label: {
                    if abs(Double(model.rate) - value) < 0.01 {
                        Label(rateText(value), systemImage: "checkmark")
                    } else {
                        Text(rateText(value))
                    }
                }
            }
        } label: {
            Text(rateText(Double(model.rate)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .monospacedDigit()
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color.white.opacity(0.14), in: Capsule())
        }
    }

    private func rateText(_ value: Double) -> String {
        value == 1 ? "倍速 1×" : "倍速 \(String(format: "%g", value))×"
    }

    // MARK: - 字幕层

    private var subtitleLayer: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                if let text = model.currentPrimaryText, !text.isEmpty {
                    SubtitleTextView(
                        text: text,
                        fontSize: settings.subtitleFontSize,
                        color: settings.subtitleColor,
                        outline: settings.subtitleOutline,
                        backgroundOpacity: settings.subtitleBackgroundOpacity
                    )
                }
                if settings.dualSubtitle,
                   let text = model.currentSecondaryText, !text.isEmpty {
                    SubtitleTextView(
                        text: text,
                        fontSize: settings.subtitleFontSize * 0.85,
                        color: settings.subtitleColor,
                        outline: settings.subtitleOutline,
                        backgroundOpacity: settings.subtitleBackgroundOpacity
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, subtitleBottomGap)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: chromeVisible)
    }

    /// 字幕到底边的距离。横屏时屏幕只有 400 点高，沿用竖屏的 118 会把字幕顶到画面正中，
    /// 所以按纵向 size class 分开取值——始终比控制栏上沿高 12~16 点。
    private var subtitleBottomGap: CGFloat {
        if verticalSizeClass == .compact {
            return chromeVisible ? 96 : 26
        }
        return chromeVisible ? 118 : 30
    }

    // MARK: - HUD 层

    @ViewBuilder
    private var hudLayer: some View {
        if let hud {
            VStack(spacing: 9) {
                Image(systemName: hud.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)

                Text(hud.text)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.white)

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

    // MARK: - 错误层

    private func errorLayer(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white.opacity(0.85))

            Text("无法播放")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)

            if !item.systemPlayable {
                Text("\(item.ext.uppercased()) 容器系统播放器不支持，需要转成 mp4 / mov，或后续接入 mpv 内核。")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            }

            Button(action: onClose) {
                Text("关闭")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 36)
                    .background(Color.white.opacity(0.18), in: Capsule())
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 330)
        .background(
            Color.black.opacity(0.78),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    // MARK: - 生命周期

    private func setup() {
        subtitles = library.subtitleFiles(for: item)
        model.onEnded = { handleEnded() }
        model.setRate(Float(settings.defaultRate))
        pendingResume = settings.resumePlayback ? progress.position(for: item.id) : 0

        if settings.autoSubtitle, let first = subtitles.first {
            model.loadPrimarySubtitle(first)
        }

        model.play()
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
        model.cleanup()
    }

    private func handleEnded() {
        progress.clear(id: item.id)
        guard settings.autoPlayNext, let next = nextItem() else {
            model.pause()
            showChrome(persistent: true)
            return
        }
        onAdvance(next)
    }

    private func nextItem() -> VideoItem? {
        guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return nil }
        let next = index + 1
        guard next < queue.count else { return nil }
        return queue[next]
    }

    private func handleSubtitleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard let saved = library.installSubtitle(from: url, for: item, secondary: subtitleImportSecondary) else {
            flashHUD(HUD(icon: "exclamationmark.triangle", text: "字幕导入失败", progress: nil), duration: 1.6)
            return
        }
        subtitles = library.subtitleFiles(for: item)
        if subtitleImportSecondary {
            model.loadSecondarySubtitle(saved)
        } else {
            model.loadPrimarySubtitle(saved)
        }
        flashHUD(HUD(icon: "captions.bubble", text: "已加载字幕", progress: nil), duration: 1.6)
    }
}

// MARK: - 字幕文本（样式可调）

struct SubtitleTextView: View {
    let text: String
    let fontSize: Double
    let color: Color
    let outline: Bool
    let backgroundOpacity: Double

    var body: some View {
        Group {
            if outline {
                base
                    .shadow(color: .black.opacity(0.95), radius: 1.5, x: 0, y: 1.5)
                    .shadow(color: .black.opacity(0.95), radius: 1.5, x: 1.5, y: 0)
                    .shadow(color: .black.opacity(0.95), radius: 1.5, x: -1.5, y: 0)
                    .shadow(color: .black.opacity(0.95), radius: 1.5, x: 0, y: -1.5)
            } else {
                base
            }
        }
        .multilineTextAlignment(.center)
        .lineSpacing(2)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(min(max(backgroundOpacity, 0), 1)))
        )
    }

    private var base: Text {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundColor(color)
    }
}
