import SwiftUI
import AVFoundation

@main
struct LocalPlayerApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var progress = ProgressStore()
    @StateObject private var settings = AppSettings()

    init() {
        #if DEBUG
        // 模拟器截图用：按启动参数生成示例视频
        DebugSeed.runIfNeeded()
        #endif

        // 允许锁屏 / 切后台继续出声
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(progress)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .tint(.accentColor)
                .onAppear { library.reload() }
        }
    }
}
