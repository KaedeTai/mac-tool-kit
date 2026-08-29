#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

VERSION="${VERSION:-$(tr -d '[:space:]' < "$DIR/VERSION")}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid VERSION: $VERSION" >&2
    exit 1
fi
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
cat << GUIDE > "$STAGING_DIR/📖 安裝與使用說明.txt"
======================================================
  MacDashboard v$VERSION（可追溯資料來源的 macOS 運作監控臺）
======================================================

【安裝方式】：
1. 將「MacDashboard」圖示直接拖曳到右側「Applications」資料夾中即可完成安裝！
2. 進入「應用程式 (Applications)」資料夾，雙擊開啟「MacDashboard」。
3. 首次開啟時，若 macOS 提示安全性保護，請至「系統設定」>「隱私權與安全性」點擊「仍要打開」。

【功能特色】：
• 溫度頁只顯示本機可驗證的具名感測來源；不同 Mac 可取得的來源數量可能不同。
• 顯示風扇實際 RPM；手動控制需安裝專用 helper，且寫入後必須有硬體讀回值才算成功。
• AI 工作分析以專案 → 主 Session → 子 Session 呈現，區分 Active、Recent 24h 與永久 History。
• 費用只在有模型與 token 證據時提供「API 等價估算」，不是實際帳單或訂閱扣款。
• 磁碟組成採具名路徑實測，清理前逐項勾選並再次確認；Docker 資料獨立呈現。
• CPU、RAM、網路、Docker、Lag 診斷與程序資料均附來源邊界，不以猜測值補空白。

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
