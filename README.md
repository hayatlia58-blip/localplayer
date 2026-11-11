# 本地播放器（iOS · 自用）

一个不上架的 iOS 本地视频播放器，SwiftUI + AVPlayer，**零第三方依赖**。

视频只存在 App 的 `Documents` 目录里，不联网、不登录、不上传任何服务器。

> 状态：源码完整（约 2600 行），设计文档见 `DESIGN.md`。
> **尚未在 Xcode 里编译过**——本人没有 macOS 环境，所有代码是静态编写的，第一次编译大概率要修几个小问题（下文列了重点检查的地方）。

## 零、想先看看长什么样

打开 `preview/ui-preview.html`（手机浏览器也可以直接开）。这是按同一套配色、间距、字号还原的**静态原型**，五个页面都能点：

| 页面 | 能点的东西 |
|---|---|
| 主页 | 视频卡片（进播放页）、网格/列表切换、搜索过滤 |
| 播放页 | 单击显隐控制栏（播放中 4 秒自动隐藏）、播放/暂停、点进度条跳转、±10 秒 HUD |
| 设置 | 字号 / 颜色 / 描边 / 背景透明度实时改变下方字幕预览 |
| Wi-Fi 传文件 | 点地址复制 |

它是**用来确认手感的，不是真实运行的 App**——真正的程序要 Xcode 编译。

---

## 一、怎么跑起来

### 前置
- macOS + Xcode 16 或更新（iOS 17 SDK）
- iPhone / iPad 真机，或模拟器

> **没有 Mac 也想装到 iPhone 上？** 跳到「方式 C」，全程在 Windows 上完成。

### 方式 A：XcodeGen（有 Mac 时最快）

```bash
brew install xcodegen          # 只需一次
cd LocalPlayer
xcodegen generate
open LocalPlayer.xcodeproj
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

### 方式 C：没有 Mac，用 GitHub 编译 + Windows 签名（推荐给你）

思路：**GitHub 的免费 macOS 机器负责编译，你自己的 Windows 负责签名安装。** 不需要 Mac，也不需要开发者账号。

**第 1 步：改 Bundle ID**
打开 `project.yml`，把 `com.example.localplayer` 改成你自己的唯一标识，例如 `com.zhangsan.localplayer`。免费 Apple ID 每个 Bundle ID 只能挂一个 App，重名会签名失败。

**第 2 步：推到 GitHub**
```bash
cd LocalPlayer
git init
git add .
git commit -m "init"
git branch -M main
git remote add origin https://github.com/你的账号/localplayer.git
git push -u origin main
```
仓库设为 **Public**（Actions 免费不限时长）或 Private（每月 2000 分钟，够用）。

**第 3 步：等 Actions 出包**
进仓库 → Actions → `Build unsigned IPA` → Run workflow，约 3–5 分钟。完成后在该次运行的底部 **Artifacts** 下载 `LocalPlayer-unsigned-ipa.zip`，解压得到 `LocalPlayer-unsigned.ipa`。

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
│   ├── LibraryStore.swift          Documents 扫描、导入、删除、建文件夹、装字幕
│   ├── ProgressStore.swift         播放进度 / 最近观看（UserDefaults）
│   ├── AppSettings.swift           全部设置项（UserDefaults 直读直写）
│   ├── SubtitleParser.swift        SRT / ASS 解析 + UTF-8→GB18030→UTF-16 编码兜底
│   ├── ThumbnailLoader.swift       首帧缩略图 + NSCache + 并发去重
│   ├── WiFiUploadServer.swift      局域网 HTTP 上传（流式写盘，不是全读进内存）
│   └── PhotoImporter.swift         相册导入，命名「20261111_001.mov」
├── Player/
│   ├── PlayerModel.swift           AVPlayer 封装：时间轴 / 轨道 / 外挂字幕 / 倍速
│   ├── VideoSurface.swift          AVPlayerLayer 的 SwiftUI 包装
│   └── PiPManager.swift            画中画
├── Views/
│   ├── LibraryView.swift           主页
│   ├── Cards.swift                 视频卡片 / 列表行 / 继续观看卡片
│   ├── PlayerScreen.swift          播放页（手势 + 控制层 + 字幕 + HUD）
│   ├── UploadView.swift            Wi-Fi 传文件（地址 + 二维码 + 接收计数）
│   └── SettingsView.swift          设置页
└── Support/
    ├── Formatters.swift            体积 / 时间格式化、重名去重
    ├── Palette.swift               配色
    ├── SystemVolume.swift          系统音量（隐藏 MPVolumeView）
    ├── ScreenBrightness.swift      屏幕亮度
    └── QRCode.swift                二维码生成
```

---

## 三、已实现

**主页**
- 继续观看（横向卡片，带剩余时长）、文件夹胶囊、视频网格 / 列表切换
- 搜索、六种排序、长按菜单（播放 / 删除）
- 空状态引导

**导入（三条通道）**
- Wi-Fi：电脑浏览器打开 `http://192.168.x.x:8080`，拖拽多文件，带进度条；流式写盘，几 G 的文件不会爆内存
- 文件 App：系统选择器，可多选，能选 SMB / 网盘挂载目录
- 相册：PhotosPicker 多选，命名 `日期_流水号`

**播放页**
- 左 1/2 竖滑 = 亮度，右 1/2 竖滑 = 音量，横滑 = 快进/快退（跟手 + HUD 目标时间）
- 双击左右 1/3 = ±10 秒，长按 = 2× 快进，双指捏合 = 适应 / 填充
- 单击显隐控制栏，播放中 4 秒自动隐藏，暂停时常驻
- 自定义进度条（可拖动，拖动时时间跟着变）
- 倍速 0.5–2.0、音轨切换、画面比例、画中画、后台播放、锁屏继续出声
- 字幕：外挂 SRT/ASS、内嵌轨道、字号 / 颜色 / 描边 / 背景透明度、双字幕
- 断点续播、同目录自动连播、结束清除进度

---

## 四、第一次编译时重点看这几处

我按最容易出问题排序，都是小改：

1. **`PlayerScreen.swift` 的双击手势**
   `.highPriorityGesture(SpatialTapGesture(count: 2))` 和 `.onTapGesture` 并存时，如果单双击互相抢，改成两个 `onTapGesture(count:)`，或把单击也换成 `SpatialTapGesture`。
2. **`onLongPressGesture(perform:onPressingChanged:)`**
   这里的 `perform` 在按住 0.35 秒后触发、`onPressingChanged(false)` 在松手时触发，用来做「长按 2×、松手恢复」。如果真机上松手没恢复速率，改用 `DragGesture(minimumDistance: 0)` + 自己计时。
3. **`PhotoImporter` 的 `FileRepresentation`**
   `MovieFile` 是标准 Apple 示例写法；如果 `loadTransferable` 一直返回 nil，把 `contentType: .movie` 换成 `.mpeg4Movie` 试试。
4. **本地网络权限**
   第一次点「Wi-Fi 传文件」系统会弹「允许查找并连接本地网络」，拒绝了就再也连不上，要去「设置 → 隐私 → 本地网络」手动打开。
5. **画中画**
   `PiPManager.attach(layer:)` 在 `makeUIView` 里调用，此时 layer 还没进 window，`AVPictureInPictureController` 可能创建失败。真机上如果 PiP 按钮没反应，改成延迟 0.5 秒再 attach。

---

## 五、两个有意的取舍

**1. Wi-Fi 上传没有用 Swifter，保留自研的流式实现。**
原计划用 `httpswift/swifter`，但它把请求体整体读进内存——传一个 4GB 的蓝光原盘会直接把 App 干掉。自己写的 `WiFiUploadServer` 边收边写盘，尾部留 2KB 用来剥离 multipart 边界。代价是只支持单文件、不支持断点续传，自用够了。

**2. 没有引 mpv。**
AVPlayer 播不了 MKV/AVI。这不是遗漏，是刻意的：PiP、AirPlay、HDR、杜比视界在 AVPlayer 上是零成本，在 mpv 上要重建整条 `AVSampleBufferDisplayLayer` 管线。
**换内核的位置只有 `PlayerModel` 一个文件**——把它的 `player: AVPlayer` 换掉、让 `VideoSurface` 换成 mpv 的渲染视图，UI 层一行都不用动。

---

## 六、下一步可以加

- 进度条长按帧预览（`AVAssetImageGenerator` 已有，加个节流就行）
- 字幕时间轴微调（±0.5 秒），改 `SubtitleParser.cue(at:)` 的入参
- 睡眠定时
- iPhone 上锁定竖屏观看（`AppDelegate` 的 `supportedInterfaceOrientationsFor`）
