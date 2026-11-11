import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var settings: AppSettings

    @State private var playingItem: VideoItem?
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var showUpload = false
    @State private var showSettings = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    @State private var gridMode = true
    @State private var searchText = ""

    @State private var toastText: String?
    @State private var toastToken = 0
    @State private var isImporting = false

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    breadcrumbSection
                    continueSection
                    folderSection
                    videoSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 64)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .overlay(alignment: .bottom) { toastView }
        .overlay { importingOverlay }
        .onAppear {
            library.reload()
            progress.refresh()
            applyDebugRoute()
        }
        .onChange(of: library.currentFolder) { _, _ in
            searchText = ""
            library.query = ""
        }
        .onChange(of: searchText) { _, value in
            library.query = value
        }
        .onChange(of: photoSelections) { _, items in
            guard !items.isEmpty else { return }
            importPhotos(items)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoSelections,
            maxSelectionCount: 20,
            matching: .videos
        )
        .fullScreenCover(item: $playingItem) { item in
            PlayerScreen(item: item, queue: library.items)
        }
        .sheet(isPresented: $showUpload) {
            UploadView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("新建文件夹", isPresented: $showNewFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) { newFolderName = "" }
            Button("创建") {
                library.createFolder(newFolderName)
                newFolderName = ""
                toast("已创建文件夹")
            }
        }
    }

    // MARK: - 调试直达（仅 Debug，用于模拟器自动截图）

    private func applyDebugRoute() {
        #if DEBUG
        guard let route = DebugSeed.argument(after: "-screen") else { return }
        // 稍微延后，避免 sheet 在 onAppear 同一帧里被丢掉
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch route {
            case "player":
                // 用 allItems 而不是 items：根目录下视频都在子文件夹里，items 是空的
                if let first = library.allItems.first {
                    if !first.folder.isEmpty { library.currentFolder = first.folder }
                    playingItem = first
                }
            case "folder":
                if let first = library.subfolders.first { library.currentFolder = first }
            case "settings":
                showSettings = true
            case "upload":
                showUpload = true
            default:
                break
            }
        }
        #endif
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)
                    Text("\(library.allItems.count) 个视频 · \(Fmt.size(library.totalSize))")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.secondaryText)
                }

                Spacer(minLength: 4)

                HStack(spacing: 7) {
                    addMenu
                    sortMenu
                    circleButton(gridMode ? "list.bullet" : "square.grid.2x2") {
                        withAnimation(.easeInOut(duration: 0.15)) { gridMode.toggle() }
                    }
                    circleButton("gearshape") { showSettings = true }
                }
            }

            searchBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Palette.background.ignoresSafeArea(edges: .top))
    }

    private var title: String {
        guard let folder = library.currentFolder else { return "本地视频" }
        return (folder as NSString).lastPathComponent
    }

    private var addMenu: some View {
        Menu {
            Button { showPhotoPicker = true } label: {
                Label("从相册导入", systemImage: "photo.on.rectangle")
            }
            Button { showFileImporter = true } label: {
                Label("从文件导入", systemImage: "folder")
            }
            Button { showUpload = true } label: {
                Label("Wi-Fi 传文件", systemImage: "wifi")
            }
            Divider()
            Button { showNewFolder = true } label: {
                Label("新建文件夹", systemImage: "folder.badge.plus")
            }
            Divider()
            Button {
                ThumbnailLoader.shared.clear()
                library.reload()
                toast("已刷新")
            } label: {
                Label("刷新缩略图", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Palette.text)
                .frame(width: 34, height: 34)
                .background(Palette.surfaceHigh, in: Circle())
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases) { option in
                Button {
                    library.sort = option
                } label: {
                    if library.sort == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.text)
                .frame(width: 34, height: 34)
                .background(Palette.surfaceHigh, in: Circle())
        }
    }

    private func circleButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.text)
                .frame(width: 34, height: 34)
                .background(Palette.surfaceHigh, in: Circle())
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12.5))
                .foregroundColor(Palette.tertiaryText)

            TextField("搜索视频", text: $searchText)
                .font(.system(size: 14))
                .foregroundColor(Palette.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    library.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Palette.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 面包屑

    @ViewBuilder
    private var breadcrumbSection: some View {
        if !library.breadcrumbs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    Button {
                        library.currentFolder = nil
                    } label: {
                        Text("全部")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Palette.accent)
                    }

                    ForEach(Array(library.breadcrumbs.enumerated()), id: \.offset) { index, path in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Palette.tertiaryText)

                        Button {
                            library.currentFolder = path
                        } label: {
                            Text((path as NSString).lastPathComponent)
                                .font(.system(size: 13, weight: index == library.breadcrumbs.count - 1 ? .semibold : .regular))
                                .foregroundColor(index == library.breadcrumbs.count - 1 ? Palette.text : Palette.secondaryText)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 继续观看

    @ViewBuilder
    private var continueSection: some View {
        if searchText.isEmpty, library.currentFolder == nil {
            let recent = progress.recentItems(from: library.allItems, limit: 10)
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("继续观看")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recent) { item in
                                Button {
                                    playingItem = item
                                } label: {
                                    RecentCard(
                                        item: item,
                                        fraction: progress.progressFraction(for: item.id),
                                        remaining: max(0, (progress.totals[item.id] ?? 0) - progress.position(for: item.id))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - 文件夹

    @ViewBuilder
    private var folderSection: some View {
        if !library.subfolders.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("文件夹")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(library.subfolders, id: \.self) { folder in
                            Button {
                                library.currentFolder = folder
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(Palette.accent)
                                    Text((folder as NSString).lastPathComponent)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Palette.text)
                                    Text("\(count(in: folder))")
                                        .font(.system(size: 11))
                                        .foregroundColor(Palette.tertiaryText)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Palette.surface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func count(in folder: String) -> Int {
        library.allItems.filter { $0.folder == folder || $0.folder.hasPrefix(folder + "/") }.count
    }

    // MARK: - 视频

    @ViewBuilder
    private var videoSection: some View {
        if library.items.isEmpty {
            if library.subfolders.isEmpty {
                emptyState
            } else {
                Text(library.allItems.isEmpty ? "此文件夹内没有视频" : "视频在上面的文件夹里，点进去就能看")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("视频 · \(library.items.count)")

                if gridMode {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 152), spacing: 12)],
                        spacing: 16
                    ) {
                        ForEach(library.items) { item in
                            cardButton(item, isGrid: true)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(library.items) { item in
                            cardButton(item, isGrid: false)
                        }
                    }
                }
            }
        }
    }

    private func cardButton(_ item: VideoItem, isGrid: Bool) -> some View {
        Button {
            playingItem = item
        } label: {
            if isGrid {
                VideoCard(item: item, fraction: progress.progressFraction(for: item.id))
            } else {
                VideoRow(item: item, fraction: progress.progressFraction(for: item.id))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                playingItem = item
            } label: {
                Label("播放", systemImage: "play.fill")
            }
            Button(role: .destructive) {
                progress.clear(id: item.id)
                library.delete(item)
                toast("已删除 \(item.displayName)")
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(Palette.secondaryText)
            .tracking(0.4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(Palette.tertiaryText)

            Text("还没有视频")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Palette.text)

            Text("用 Wi-Fi 从电脑传，或从相册 / 文件 App 导入\n视频只存在本机，不上传任何服务器")
                .font(.system(size: 12.5))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .foregroundColor(Palette.tertiaryText)

            VStack(spacing: 8) {
                Button {
                    showUpload = true
                } label: {
                    Label("Wi-Fi 传文件", systemImage: "wifi")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Palette.accent, in: Capsule())
                }

                HStack(spacing: 8) {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("相册", systemImage: "photo.on.rectangle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Palette.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Palette.surfaceHigh, in: Capsule())
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("文件", systemImage: "folder")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Palette.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Palette.surfaceHigh, in: Capsule())
                    }
                }
            }
            .padding(.top, 2)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - 浮层

    @ViewBuilder
    private var toastView: some View {
        if let toastText {
            Text(toastText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Palette.surfaceHigh, in: Capsule())
                .padding(.bottom, 26)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var importingOverlay: some View {
        if isImporting {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("正在从相册导入…")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
                .background(Palette.surfaceHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - 动作

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let count = library.importURLs(urls)
            toast(count > 0 ? "已导入 \(count) 个文件" : "没有导入成功")
        case .failure:
            toast("导入失败")
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        isImporting = true
        let folder = library.currentFolder
        Task {
            let count = await PhotoImporter.importItems(items, into: folder, library: library)
            await MainActor.run {
                isImporting = false
                photoSelections = []
                toast(count > 0 ? "已从相册导入 \(count) 个视频" : "没有导入成功")
            }
        }
    }

    private func toast(_ text: String) {
        toastToken += 1
        let token = toastToken
        withAnimation(.easeOut(duration: 0.15)) { toastText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if toastToken == token {
                withAnimation(.easeIn(duration: 0.2)) { toastText = nil }
            }
        }
    }
}
