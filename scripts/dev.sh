#!/usr/bin/env bash
# 在 macOS 上运行（本机 Mac 或云 Mac 都行）：
#   1. 生成 Xcode 工程
#   2. 编译到模拟器
#   3. 启动模拟器、装进去、带上 4 段示例视频打开
#
# 用法：bash scripts/dev.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> 安装 XcodeGen"
  brew install xcodegen
fi

echo "==> 生成 Xcode 工程"
xcodegen generate

UDID=$(xcrun simctl list devices available | grep -E "iPhone" | head -1 \
       | grep -oE "[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}" || true)
if [ -z "$UDID" ]; then
  echo "找不到可用的 iPhone 模拟器，请先在 Xcode 里下载 iOS Simulator"
  exit 1
fi
echo "==> 使用模拟器 $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator

echo "==> 编译"
xcodebuild \
  -project LocalPlayer.xcodeproj \
  -scheme LocalPlayer \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "id=$UDID" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="build/Build/Products/Debug-iphonesimulator/LocalPlayer.app"
echo "==> 安装并启动"
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.example.localplayer -screen home -seedDemo 1

echo
echo "完成。模拟器里就是它真实的样子。"
echo "想直接看某一屏，可以改成本行重跑："
echo "  xcrun simctl terminate $UDID com.example.localplayer; \\"
echo "  xcrun simctl launch $UDID com.example.localplayer -screen player"
echo "（-screen 可选 home / player / settings / upload / empty）"
