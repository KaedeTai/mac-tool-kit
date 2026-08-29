#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$DIR/VERSION")}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid VERSION: $VERSION" >&2
    exit 1
fi

echo "🔨 Building MacDashboard in Release mode..."

mkdir -p .tmp .clang-cache .module-cache
TMPDIR="$DIR/.tmp" \
CLANG_MODULE_CACHE_PATH="$DIR/.clang-cache" \
SWIFT_MODULECACHE_OVERRIDE_DIRECTORY="$DIR/.module-cache" \
swift build -c release --disable-sandbox --scratch-path .build -Xswiftc -module-cache-path -Xswiftc "$DIR/.module-cache"

APP_NAME="MacDashboard.app"
APP_BUNDLE="$DIR/$APP_NAME"

echo "📦 Packaging $APP_NAME..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/arm64-apple-macosx/release/MacDashboardApp" "$APP_BUNDLE/Contents/MacOS/MacDashboardApp" 2>/dev/null || \
cp ".build/release/MacDashboardApp" "$APP_BUNDLE/Contents/MacOS/MacDashboardApp"

# Copy MacDashboardFanHelper to Resources and MacOS
cp ".build/arm64-apple-macosx/release/MacDashboardFanHelper" "$APP_BUNDLE/Contents/Resources/MacDashboardFanHelper" 2>/dev/null || \
cp ".build/release/MacDashboardFanHelper" "$APP_BUNDLE/Contents/Resources/MacDashboardFanHelper" 2>/dev/null || true

# Copy AppIcon.icns if present
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat << PLIST > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacDashboardApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.peterting.mac-tool-kit.dashboard</string>
    <key>CFBundleName</key>
    <string>Mac Dashboard</string>
    <key>CFBundleDisplayName</key>
    <string>Mac Dashboard</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

# SwiftPM emits linker-signed Mach-O files. Sign the completed application
# bundle so Info.plist and Resources are sealed as part of the app identity.
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "✅ Successfully built: $APP_BUNDLE"

if [ -d "/Applications/$APP_NAME" ] || [ "$INSTALL" = "1" ]; then
    echo "📲 Updating /Applications/$APP_NAME..."
    DASHBOARD_PID="$(pgrep -x MacDashboardApp || true)"
    if [ -n "$DASHBOARD_PID" ] && [ "$(ps -p "$DASHBOARD_PID" -o command=)" = "/Applications/$APP_NAME/Contents/MacOS/MacDashboardApp" ]; then
        kill "$DASHBOARD_PID"
    fi
    sleep 0.5
    rm -rf "/Applications/$APP_NAME"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME"
    codesign --verify --deep --strict "/Applications/$APP_NAME"
    echo "🚀 Installed to /Applications/$APP_NAME"
fi
