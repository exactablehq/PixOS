#!/bin/bash
set -e

echo "🚀 Building PixOS Native macOS Application (Release)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

# 1. Build release binaries
swift build -c release --build-system native --product PixOSApp
swift build -c release --build-system native --product pixos

APP_DIR="$ROOT_DIR/build/PixOS.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources/bin"

# 2. Copy App Executable
cp "$ROOT_DIR/.build/release/PixOSApp" "$APP_DIR/Contents/MacOS/PixOSApp"
chmod +x "$APP_DIR/Contents/MacOS/PixOSApp"

# 3. Copy Bundled ADB
if [ -f "$ROOT_DIR/bin/adb" ]; then
    cp "$ROOT_DIR/bin/adb" "$APP_DIR/Contents/Resources/bin/adb"
    chmod +x "$APP_DIR/Contents/Resources/bin/adb"
fi

# 4. Generate Info.plist
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PixOSApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.exactable.PixOS</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PixOS</string>
    <key>CFBundleDisplayName</key>
    <string>PixOS</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>PixOS accesses your iPhone camera roll to extract and backup photos to your Google Pixel.</string>
</dict>
</plist>
EOF

# 5. Ad-hoc code sign
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "✔ Successfully generated $APP_DIR"
