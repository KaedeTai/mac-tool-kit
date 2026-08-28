#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

VERSION="1.0.0"
DMG_NAME="MacDashboard-v${VERSION}-macOS.dmg"
ZIP_NAME="MacDashboard-v${VERSION}-macOS.zip"
DIST_DIR="$DIR/dist"
STAGING_DIR="$DIR/.build/dmg_staging"

echo "🔨 Building MacDashboard Release App..."
./scripts/build_app.sh

echo "📦 Preparing packaging workspace in $DIST_DIR..."
rm -rf "$DIST_DIR" "$STAGING_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR"

# Copy App to Staging
cp -R "$DIR/MacDashboard.app" "$STAGING_DIR/"

# Create /Applications symlink for easy drag-and-drop installation
ln -s /Applications "$STAGING_DIR/Applications"

# Add User-friendly Installation & Usage Guide
cat << 'GUIDE' > "$STAGING_DIR/📖 安裝與使用說明.txt"
======================================================
  MacDashboard (macOS 頂級全能監控與智慧溫控工具箱)
======================================================

【安裝方式】：
1. 將「MacDashboard」圖示直接拖曳到右側「Applications」資料夾中即可完成安裝！
2. 進入「應用程式 (Applications)」資料夾，雙擊開啟「MacDashboard」。
3. 首次開啟時，若 macOS 提示安全性保護，請至「系統設定」>「隱私權與安全性」點擊「仍要打開」。

【功能特色】：
• 8 大核心硬體即時溫度（Apple Silicon SoC、CPU、GPU、ANE、統一記憶體、掌托電池、散熱鰭片、SSD）。
• 智慧閉迴路自訂元件溫控（支援掌托降溫、SoC 壓溫、手動固定轉速）。
• LagDetective 卡頓偵探（智慧追蹤 Lag 根因並提供一鍵解決方案）。
• 磁碟、網路、記憶體、CPU 多核心、Docker 與程序深度監控。

祝您使用愉快！
GUIDE

echo "💿 Creating DMG Disk Image ($DMG_NAME)..."
hdiutil create \
    -volname "MacDashboard Installer" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$DMG_NAME"

echo "🤐 Creating portable ZIP Archive ($ZIP_NAME)..."
cd "$DIR"
ditto -c -k --keepParent "MacDashboard.app" "$DIST_DIR/$ZIP_NAME"

rm -rf "$STAGING_DIR"

echo "======================================================"
echo "🎉 打包完成！已生成可供分享與安裝的檔案："
echo "   1. 💿 DMG 安裝映像檔: $DIST_DIR/$DMG_NAME"
echo "   2. 🤐 免安裝 ZIP 壓縮包: $DIST_DIR/$ZIP_NAME"
echo "======================================================"
