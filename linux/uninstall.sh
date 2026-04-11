#!/usr/bin/env bash
# AIHelper Linux uninstaller
set -euo pipefail

INSTALL_BIN="$HOME/.local/bin"
INSTALL_APP="$HOME/.local/share/applications"
INSTALL_ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"
CONFIG_AUTOSTART="$HOME/.config/autostart"
CONFIG_DIR="$HOME/.config/aihelper"

echo "==> AIHelper Linux Uninstaller"
echo ""

# Remove launcher
if [[ -f "$INSTALL_BIN/aihelper" ]]; then
    rm -f "$INSTALL_BIN/aihelper"
    echo "  Removed $INSTALL_BIN/aihelper"
fi

# Remove .desktop files
for f in "$INSTALL_APP/aihelper.desktop" "$CONFIG_AUTOSTART/aihelper.desktop"; do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        echo "  Removed $f"
    fi
done
update-desktop-database "$INSTALL_APP" 2>/dev/null || true

# Remove icon
if [[ -f "$INSTALL_ICONS/aihelper.svg" ]]; then
    rm -f "$INSTALL_ICONS/aihelper.svg"
    echo "  Removed icon"
fi
gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

# Optionally remove config
read -rp "==> Remove config (~/.config/aihelper)? This deletes saved settings. [y/N] " _rmcfg
if [[ "${_rmcfg,,}" == "y" ]]; then
    rm -rf "$CONFIG_DIR"
    echo "  Removed $CONFIG_DIR"
fi

echo ""
echo "✅  AIHelper uninstalled."
