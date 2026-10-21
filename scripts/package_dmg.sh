#!/bin/bash
set -e

echo "📦 Packaging PixOS DMG for macOS Distribution..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 1. Build app first
bash "$SCRIPT_DIR/build_app.sh"

DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg_staging"
DMG_PATH="$DIST_DIR/PixOS-1.0.0.dmg"

rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH"
mkdir -p "$STAGING_DIR"

# 2. Copy PixOS.app into staging
cp -R "$ROOT_DIR/build/PixOS.app" "$STAGING_DIR/PixOS.app"

# 3. Create Applications symlink for standard macOS drag-and-drop install flow
ln -s /Applications "$STAGING_DIR/Applications"

# 4. Copy standalone CLI executable and install helper
cp "$ROOT_DIR/.build/release/pixos" "$STAGING_DIR/pixos"
cat << 'EOF' > "$STAGING_DIR/install_cli.sh"
#!/bin/bash
echo "Installing 'pixos' command line tool to /usr/local/bin..."
sudo cp "$(dirname "$0")/pixos" /usr/local/bin/pixos
sudo chmod +x /usr/local/bin/pixos
echo "✔ Successfully installed pixos CLI! Run 'pixos help' to get started."
EOF
chmod +x "$STAGING_DIR/install_cli.sh"

# 5. Build DMG using hdiutil
echo "Creating compressed read-only DMG image..."
hdiutil create \
    -volname "PixOS" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "--------------------------------------------------------"
echo "✔ PixOS DMG Created Successfully!"
echo "Location: $DMG_PATH"
ls -lh "$DMG_PATH"
echo "--------------------------------------------------------"
