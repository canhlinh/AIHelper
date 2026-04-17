#!/usr/bin/env bash
set -e

BINARY_NAME="aihelper"
APP_ID="dev.lingcloud.aihelper"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
AUTOSTART_DIR="$HOME/.config/autostart"

# ── 1. System dependencies ────────────────────────────────────────────
echo ">>> Installing system dependencies..."
sudo dnf install -y \
    gtk4-devel libsecret-devel glib2-devel dbus-devel \
    wl-clipboard ydotool \
    2>&1 | grep -E "^(Installing|Already|Error|nothing)" || true

# ── 2. ydotool daemon (for paste-back feature) ────────────────────────
echo ">>> Configuring ydotool daemon..."
sudo mkdir -p /etc/systemd/system/ydotool.service.d
sudo tee /etc/systemd/system/ydotool.service.d/socket-perms.conf > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/ydotoold --socket-own $(id -u):$(id -g) --socket-perm 0600
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now ydotool.service || echo "  (ydotool service not available, paste-back will be limited)"

# ── 3. Build ──────────────────────────────────────────────────────────
echo ">>> Building AIHelper (release)..."
cargo build --release

# ── 4. Install binary ─────────────────────────────────────────────────
echo ">>> Installing binary..."
mkdir -p "$BIN_DIR"
cp "target/release/$BINARY_NAME" "$BIN_DIR/$BINARY_NAME"
chmod +x "$BIN_DIR/$BINARY_NAME"

# ── 5. Icons ──────────────────────────────────────────────────────────
echo ">>> Installing icons..."
ICON_SRC="icons"
ICON_DIR="$HOME/.local/share/icons/hicolor"
mkdir -p "$ICON_DIR/16x16/apps" "$ICON_DIR/32x32/apps" "$ICON_DIR/128x128/apps" "$ICON_DIR/256x256/apps" "$ICON_DIR/512x512/apps"
cp "$ICON_SRC/16.png"  "$ICON_DIR/16x16/apps/aihelper.png"
cp "$ICON_SRC/32.png"  "$ICON_DIR/32x32/apps/aihelper.png"
cp "$ICON_SRC/128.png" "$ICON_DIR/128x128/apps/aihelper.png"
cp "$ICON_SRC/256.png" "$ICON_DIR/256x256/apps/aihelper.png"
cp "$ICON_SRC/512.png" "$ICON_DIR/512x512/apps/aihelper.png"
gtk-update-icon-cache -f "$ICON_DIR" 2>/dev/null || true

# ── 6. Desktop entry + autostart ─────────────────────────────────────
mkdir -p "$DESKTOP_DIR" "$AUTOSTART_DIR"

# Desktop file name must match the app ID for D-Bus activation to work
cat > "$DESKTOP_DIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Name=AIHelper
Comment=AI writing assistant
Exec=$BIN_DIR/$BINARY_NAME
Icon=aihelper
Type=Application
Categories=Utility;
StartupNotify=false
EOF

cat > "$AUTOSTART_DIR/$BINARY_NAME.desktop" <<EOF
[Desktop Entry]
Name=AIHelper
Exec=$BIN_DIR/$BINARY_NAME
Type=Application
X-GNOME-Autostart-enabled=true
EOF

update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true

# ── Done ──────────────────────────────────────────────────────────────
echo ""
echo "✅ Done! AIHelper installed to $BIN_DIR/$BINARY_NAME"
echo "   It will auto-start on next login."
echo "   To run now: $BINARY_NAME"
