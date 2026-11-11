# 本地播放器（iOS · 自用）

一个不上架的 iOS 本地视频播放器，SwiftUI + AVPlayer，**零第三方依赖**。

视频只存在 App 的 `Documents` 目录里，不联网、不登录、不上传任何服务器。

> 状态：**已在 macOS 上编译通过，并在 iPhone 模拟器里跑起来截图**（19 个 Swift 文件，约 2900 行）。设计文档见 `DESIGN.md`。
> 功能范围：本地导入 + 播放 + 断点续播 + 手势 + 画中画。**不含字幕、不含局域网传输**（见 `DESIGN.md` 第 6 节）。

## 零、三种「看到它」的方式

| 方式 | 真实性 | 成本 | 适合 |
|---|---|---|---|
| **静态原型** `preview/ui-preview.html` | 只是布局还原，不能播视频 | 0 | 先确认配色、间距、交互手感 |
| **CI 模拟器截图**（GitHub Actions） | **真实编译 + 真实 SwiftUI 渲染** | 0（Public 仓库免费） | 想看真机效果，但没有 Mac |
| **云 Mac 亲手跑**（Xcode + 模拟器） | 完全真实，可以打断点、改代码 | $0.99 起 | 想自己调、自己改 |

静态原型里能点的东西：主页→播放页、网格/列表切换、搜索过滤、点进度条跳转。它还原的是 v0.1（含传文件页和字幕设置），当前代码已移除这两块，**布局以 CI 截图为准**。

---

## 一、怎么跑起来

### 前置
- macOS + Xcode 16 或更新（iOS 17 SDK）
- iPhone / iPad 真机，或模拟器

> **没有 Mac？** 见「方式 B」（GitHub 编译，出截图和 ipa）或「方式 C」（租云 Mac，亲手跑 Xcode）。

### 方式 A：XcodeGen（有 Mac 时最快）

```bash
brew install xcodegen          # 只需一次
cd LocalPlayer
xcodegen generate
open LocalPlayer.xcodeproj
```

或者一条命令直接编译 + 装进模拟器并带上示例视频：

```bash
bash scripts/dev.sh
```

然后在 Xcode 里：
1. 选中 `LocalPlayer` target → Signing & Capabilities → 填你的 Team（免费 Apple ID 也行）
2. 把 `PRODUCT_BUNDLE_IDENTIFIER` 改成你自己的（如 `com.你的名字.localplayer`）
3. 选真机 → Run

### 方式 B：不用 XcodeGen，手动建工程

1. Xcode → New Project → iOS → App
2. Product Name 填 `LocalPlayer`，Interface 选 **SwiftUI**，Language 选 **Swift**，最低版本选 **iOS 17.0**
3. 删掉模板生成的 `ContentView.swift` 和 `LocalPlayerApp.swift`
4. 把本仓库的 `LocalPlayer/` 整个文件夹**拖进** Xcode（勾选 Create groups，不要勾 Copy items）
5. 打开 Target → Info，把 `Info.plist` 的键值逐条搬进去（或直接删掉模板 Info.plist，改用本仓库的 `Info.plist`，并在 Build Settings → Packaging → Info.plist File 指向它）

### 方式 B：没有 Mac，用 GitHub 编译（免费，能出真实截图）

思路：**GitHub 的免费 macOS 机器负责编译，你自己的 Windows 负责签名安装。** 不需要 Mac，也不需要开发者账号。

仓库里的 workflow（`.github/workflows/ios-ipa.yml`）跑两个任务：

| 任务 | 产出 | 说明 |
|---|---|---|
| `simulator` | `simulator-screenshots`（6 张 PNG） | 真的把 App 装进 iOS 模拟器、启动、逐屏截图；同时上传 `xcodebuild-log` |
| `ipa` | `LocalPlayer-unsigned-ipa` | Release 未签名 ipa，装机用 |

截图覆盖：空状态 / 主页（含「继续观看」）/ 文件夹网格 / 播放页竖屏 / 播放页横屏 / 设置。
调试用的启动参数（只在 Debug 生效，写在 `Support/DebugSeed.swift`）：

| 参数 | 作用 |
|---|---|
| `-screen home\|folder\|player\|settings\|upload\|empty` | 启动后直达某一屏 |
| `-seedDemo 1` | 现场生成 4 段 8 秒示例视频 + 两条播放记录 |
| `-keepChrome 1` | 钉住播放控制栏（否则 4 秒后自动隐藏，截图拍不到） |
| `-landscape 1` | 调 `requestGeometryUpdate` 真把 App 转到横屏 |

**第 1 步：改 Bundle ID**
打开 `project.yml`，把 `com.example.localplayer` 改成你自己的唯一标识，例如 `com.zhangsan.localplayer`。免费 Apple ID 每个 Bundle ID 只能挂一个 App，重名会签名失败。

**第 2 步：推到 GitHub**（本地仓库已经初始化并提交好了，只差一个远端）
先在 GitHub 网页上新建一个空仓库（不要勾 README / .gitignore），然后：
```bash
cd LocalPlayer
git remote add origin https://github.com/你的账号/localplayer.git
git push -u origin main
```
仓库设为 **Public**（Actions 免费不限时长）或 Private（每月 2000 分钟，够用）。

**第 3 步：等 Actions 出结果**
进仓库 → Actions → 左侧选 `Build & Screenshot` → Run workflow，约 3–5 分钟。
- 想看真实界面：下载 `simulator-screenshots`
- 编译报错了：下载 `xcodebuild-log`，把 `error:` 那几行发我
- 想装机：下载 `LocalPlayer-unsigned-ipa`

**第 4 步：Windows 上装 Sideloadly**
下载 <https://sideloadly.io> → 数据线连 iPhone → 把 ipa 拖进窗口 → 填 Apple ID → Start。

> 首次需要在 iPhone 上「设置 → 通用 → VPN 与设备管理」里信任你的开发者证书；
> iOS 16 以上还要在「设置 → 隐私与安全性 → 开发者模式」打开开发者模式并重启。

**第 5 步：7 天到期后续签**
免费证书有效期 7 天，到期 App 打不开。两种处理：
- 再用 Sideloadly 装一次（覆盖安装，数据一般保留）
- 或者装 **AltStore / SideStore**，同一 Wi-Fi 下自动续签，不用连电脑

**这个方式的天花板**（提前讲清，省得后面踩坑）：
- 免费账号最多同时装 **3 个**自签名 App，证书 7 天一续
- 删掉 App 再装，`Documents` 里的视频**会一起没**——重要片子先在「文件」App 里留一份
- 后台播放、画中画、锁屏控制**都正常**，这几项不需要付费账号的 entitlement

### 方式 C：租一台云 Mac，亲手在 Xcode 里跑

想自己拖界面、打断点、看真实动画，就必须有一台 macOS。目前最便宜的临时方案：

| 平台 | 价格 | 说明 |
|---|---|---|
| **MacinCloud** | 首单 **$0.99 / 24 小时**；按需 $1/小时；包月 $25 起 | 选 Pay-As-You-Go，镜像自带 Xcode 和 iOS 模拟器 |
| Scaleway Mac mini | €0.11–0.22/小时，包月 €75 起 | 更便宜，但开通要审核 |
| AWS EC2 Mac | 约 $1.48/小时，**24 小时起租** | 不适合临时用 |

登录进去之后，把整个 `LocalPlayer` 文件夹传上去（网页文件管理或 `git clone`），终端里一条命令：

```bash
bash scripts/dev.sh
```

它会依次做：装 XcodeGen → 生成工程 → 编译 → 启动模拟器 → 安装 → 生成 4 段示例视频并打开首页。成功后你就在模拟器里看到真东西了，可以直接改代码、Cmd+R 重跑。

> 云 Mac 上插不了你的 iPhone，所以它的作用是**验证和调界面**，装机仍走「方式 B 出 ipa + Sideloadly 签名」那条链。

### 有 Mac 的话，装到手机上（自用）

| 方式 | 有效期 | 说明 |
|---|---|---|
| 免费 Apple ID + Xcode | 7 天 | 到期用 AltStore / SideStore 续签，或在 Xcode 里重新 Run 一次 |
| 开发者账号 $99/年 | 1 年 | 省心，能装 100 台设备 |
| TrollStore | 永久 | 只支持 iOS 14.0–16.x 及部分 17.0，能装就最爽 |

---

## 二、目录结构

```
LocalPlayer/
├── App/
│   └── LocalPlayerApp.swift        @main，注入三个 store，配 AVAudioSession
├── Models/
│   └── VideoItem.swift             视频条目（相对路径即稳定 ID）、排序枚举
├── Services/
│   ├── LibraryStore.swift          Documents 扫描、导入、删除、建文件夹
│   ├── ProgressStore.swift         播放进度 / 最近观看（UserDefaults）
│   ├── AppSettings.swift           全部设置项（UserDefaults 直读直写）
│   ├── ThumbnailLoader.swift       首帧缩略图 + NSCache + 并发去重
│   └── PhotoImporter.swift         相册导入，命名「20261111_001.mov」
├── Player/
│   ├── PlayerModel.swift           AVPlayer 封装：时间轴 / 音轨 / 倍速 / 缓冲状态
│   ├── VideoSurface.swift          AVPlayerLayer 的 SwiftUI 包装
│   └── PiPManager.swift            画中画
├── Views/
│   ├── LibraryView.swift           主页
│   ├── Cards.swift                 视频卡片 / 列表行 / 继续观看卡片
│   ├── PlayerScreen.swift          播放页（手势 + 控制层 + HUD）
│   └── SettingsView.swift          设置页
└── Support/
    ├── Formatters.swift            体积 / 时间格式化、重名去重
    ├── Palette.swift               配色
    ├── SystemVolume.swift          系统音量（隐藏 MPVolumeView）
    ├── ScreenBrightness.swift      屏幕亮度
    └── DebugSeed.swift             仅 Debug：生成示例视频（CI 截图 / 本地调试用）
```

另外两处工程文件：

| 文件 | 作用 |
|---|---|
| `LocalPlayer/Assets.xcassets` | AppIcon（1024 单尺寸）+ AccentColor `#5A8BFF` |
| `scripts/dev.sh` | macOS 上一键：生成工程 → 编译 → 装模拟器 → 带示例数据启动 |
| `.github/workflows/ios-ipa.yml` | CI：模拟器截图 + 未签名 ipa |

---

## 三、已实现

**主页**
- 继续观看（横向卡片，带剩余时长）、文件夹胶囊、视频网格 / 列表切换
- 搜索、六种排序、长按菜单（播放 / 删除）
- 空状态引导

**导入（两条通道）**
- 文件 App：系统选择器，可多选，能选 SMB / 网盘挂载目录；也能用访达 / iTunes 文件共享直接拖进 Documents
- 相册：PhotosPicker 多选，命名 `日期_流水号`

**播放页**
- 左 1/2 竖滑 = 亮度，右 1/2 竖滑 = 音量，横滑 = 快进/快退（跟手 + HUD 目标时间）
- 双击左右 1/3 = ±10 秒，长按 = 2× 快进，双指捏合 = 适应 / 填充
- 单击显隐控制栏，播放中 4 秒自动隐藏，暂停时常驻
- 自定义进度条（可拖动，拖动时时间跟着变）
- 倍速 0.5–2.0、音轨切换、画面比例、画中画、后台播放、锁屏继续出声
- 断点续播、同目录自动连播、结束清除进度

---

## 四、编译状态与已发现的问题

**已经在 GitHub 的 macOS 机器上真实编译通过，并在 iPhone 模拟器里跑起来截图了。** 前几轮出现的编译错误全部是 API 名字写错，已修：

| 文件 | 报错 | 修法 |
|---|---|---|
| `Player/VideoSurface.swift` | `AVVideoGravity` 不存在 | 改 `AVLayerVideoGravity` |
| `Services/PhotoImporter.swift` | 找不到 `PhotosPickerItem` | 补 `import SwiftUI`（PhotosUI 的 SwiftUI 支持是交叉覆盖模块） |
| `Player/PlayerModel.swift` | `mediaSelectionGroup(for:)` 标签错 | 改 `forMediaCharacteristic:` |

截图过程中发现并修掉的界面问题：

1. **体积显示成 `0 MB`**——`ByteCountFormatter` 只放了 `.useMB/.useGB`，小文件被四舍五入成 0，已放开到 KB。
2. **根目录空提示误导**——视频都在子文件夹里，根目录却写「此文件夹内没有视频」。
3. **播放页右下角显示文件体积**——看片时这个数字没用，改成剩余时间 `−00:03`。

### 还要在真机上确认的（模拟器测不出来）

1. **长按 2× 快进**：`onLongPressGesture(perform:onPressingChanged:)` 的松手回调在真机上才准，模拟器鼠标事件可能不触发。
2. **双击 ±10 秒**：`SpatialTapGesture(count: 2)` 与单击手势并存，模拟器上看不出抢事件，真机上确认单击能正常显隐控制栏。
3. **画中画**：`PiPManager.attach(layer:)` 在 `makeUIView` 里调用，此时 layer 可能还没进 window；PiP 按钮没反应就改成延迟 0.5 秒 attach。
4. **相册导入**：`PhotoImporter` 的 `FileRepresentation` 用 `.movie`，个别 iCloud 未下载的原片可能返回 nil，届时换 `.mpeg4Movie` 或先 `startDownloadingCloudPhotos`。

---

## 五、两个有意的取舍

**1. 砍掉了字幕和局域网传输。**
v0.1 里这两块占了近三分之一复杂度：一个手写 HTTP multipart 服务（还要处理大文件流式写盘、边界剥离）、一个带 GB18030 编码兜底的 SRT/ASS 解析器加完整样式系统。实际用下来都不需要——电脑传文件直接走访达的文件共享或「文件」App 拖拽，字幕则没几部片子用得着。删完之后少 4 个文件、约 900 行，权限也少申请一个（本地网络）。

**2. 没有引 mpv。**
AVPlayer 播不了 MKV/AVI。这不是遗漏，是刻意的：PiP、AirPlay、HDR、杜比视界在 AVPlayer 上是零成本，在 mpv 上要重建整条 `AVSampleBufferDisplayLayer` 管线。
**换内核的位置只有 `PlayerModel` 一个文件**——把它的 `player: AVPlayer` 换掉、让 `VideoSurface` 换成 mpv 的渲染视图，UI 层一行都不用动。

---

## 六、下一步可以加

- 进度条长按帧预览（`AVAssetImageGenerator` 已有，加个节流就行）
- 睡眠定时
- iPhone 上锁定竖屏观看（`AppDelegate` 的 `supportedInterfaceOrientationsFor`）
