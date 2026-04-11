#!/usr/bin/env bash
# AIHelper Linux installer for Fedora 43
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_BIN="$HOME/.local/bin"
INSTALL_APP="$HOME/.local/share/applications"
INSTALL_ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"
CONFIG_AUTOSTART="$HOME/.config/autostart"

echo "==> AIHelper Linux Installer"
echo ""

# ---------------------------------------------------------------------------
# 1. System packages (Fedora / dnf)
# ---------------------------------------------------------------------------
if command -v dnf &>/dev/null; then
    echo "==> Installing system packages via dnf (may ask for sudo password)..."
    sudo dnf install -y \
        python3 \
        python3-pip \
        python3-gobject \
        python3-gobject-devel \
        gtk4 \
        gtk4-devel \
        libayatana-appindicator \
        libayatana-appindicator-devel \
        webkit2gtk4.1 \
        webkit2gtk4.1-devel \
        xdotool \
        wl-clipboard \
        libsecret \
        gnome-keyring \
        python3-keyring 2>/dev/null || true

    # ydotool is optional (Wayland key injection)
    sudo dnf install -y ydotool 2>/dev/null || echo "  [note] ydotool not available – Wayland key injection will be limited"
else
    echo "  [warn] dnf not found – skipping system package installation."
    echo "         Please install GTK4, WebKit2GTK 4.1, and AppIndicator manually."
fi

# ---------------------------------------------------------------------------
# 2. Python packages
# ---------------------------------------------------------------------------
echo ""
echo "==> Installing Python packages..."
pip install --user --upgrade pip --quiet
pip install --user \
    "pynput>=1.7.6" \
    "keyring>=24.0.0" \
    "requests>=2.31.0" \
    "mistune>=3.0.0" \
    "pystray>=0.19.0" \
    "Pillow>=10.0.0"

# ---------------------------------------------------------------------------
# 3. Create launcher
# ---------------------------------------------------------------------------
echo ""
echo "==> Installing launcher to $INSTALL_BIN/aihelper ..."
mkdir -p "$INSTALL_BIN"

cat > "$INSTALL_BIN/aihelper" <<EOF
#!/usr/bin/env bash
exec python3 "$SCRIPT_DIR/aihelper.py" "\$@"
EOF
chmod +x "$INSTALL_BIN/aihelper"

# Make sure ~/.local/bin is on PATH
if [[ ":$PATH:" != *":$INSTALL_BIN:"* ]]; then
    echo ""
    echo "  [note] $INSTALL_BIN is not in PATH."
    echo "         Add the following line to your ~/.bashrc or ~/.zshrc:"
    echo "         export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ---------------------------------------------------------------------------
# 4. Desktop entry
# ---------------------------------------------------------------------------
echo ""
echo "==> Installing .desktop entry..."
mkdir -p "$INSTALL_APP"
sed "s|Exec=aihelper|Exec=$INSTALL_BIN/aihelper|g" "$SCRIPT_DIR/aihelper.desktop" \
    > "$INSTALL_APP/aihelper.desktop"
update-desktop-database "$INSTALL_APP" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 5. Icon (SVG inline fallback)
# ---------------------------------------------------------------------------
mkdir -p "$INSTALL_ICONS"
if [[ ! -f "$INSTALL_ICONS/aihelper.svg" ]]; then
    cat > "$INSTALL_ICONS/aihelper.svg" <<'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#4A9EFF" d="M20 2H4C2.9 2 2 2.9 2 4v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"/>
  <text x="12" y="15" text-anchor="middle" fill="white" font-size="10" font-family="sans-serif">AI</text>
</svg>
SVGEOF
    echo "  Installed icon: $INSTALL_ICONS/aihelper.svg"
fi
gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 6. Optional: autostart entry
# ---------------------------------------------------------------------------
read -rp "==> Add AIHelper to autostart? [y/N] " _autostart
if [[ "${_autostart,,}" == "y" ]]; then
    mkdir -p "$CONFIG_AUTOSTART"
    cp "$INSTALL_APP/aihelper.desktop" "$CONFIG_AUTOSTART/aihelper.desktop"
    echo "  Autostart entry created: $CONFIG_AUTOSTART/aihelper.desktop"
fi

echo ""
echo "✅  Installation complete!"
echo "   Run 'aihelper' to start, or launch from your application menu."
