"""
main.py – GTK4 Application entry point.

Responsibilities:
- Load settings
- Create the system tray icon
- Start the global hotkey manager
- On hotkey: capture selected text, show PopupWindow
- Open SettingsWindow from tray
"""

from __future__ import annotations

import sys
import threading
from typing import Optional

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gtk, Gdk, GLib, Gio  # type: ignore

# ---------------------------------------------------------------------------
# Tray icon – try AyatanaAppIndicator3, then AppIndicator3, then pystray
# ---------------------------------------------------------------------------

_tray_backend: str = "none"

try:
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3 as AppIndicator  # type: ignore
    _tray_backend = "ayatana"
except Exception:
    try:
        gi.require_version("AppIndicator3", "0.1")
        from gi.repository import AppIndicator3 as AppIndicator  # type: ignore
        _tray_backend = "appindicator"
    except Exception:
        AppIndicator = None  # type: ignore

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------


class AIHelperApp(Gtk.Application):
    """Main GtkApplication."""

    def __init__(self) -> None:
        super().__init__(
            application_id="io.github.aihelper",
            flags=Gio.ApplicationFlags.FLAGS_NONE,
        )
        self._popup: Optional[object] = None
        self._settings_win: Optional[object] = None
        self._hotkey_manager: Optional[object] = None
        self._tray_indicator = None
        self._tray_pystray = None

        self.connect("activate", self._on_activate)

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def _on_activate(self, _app) -> None:
        from .settings_store import SettingsStore

        store = SettingsStore()
        self._store = store

        self._start_hotkey_manager(store.settings.hotkey)
        self._setup_tray()

        # Keep the app alive (no main window)
        self.hold()

    # ------------------------------------------------------------------
    # Hotkey
    # ------------------------------------------------------------------

    def _start_hotkey_manager(self, hotkey_str: str) -> None:
        from .hotkey_manager import HotkeyManager
        self._hotkey_manager = HotkeyManager(on_activate=self._on_hotkey_triggered)
        self._hotkey_manager.start(hotkey_str)

    def _on_hotkey_triggered(self) -> None:
        """Called on GLib main loop (via GLib.idle_add in HotkeyManager)."""
        from .clipboard_manager import ClipboardManager

        def _do_copy():
            text = ClipboardManager().copy_selection()
            GLib.idle_add(self._show_popup, text)

        threading.Thread(target=_do_copy, daemon=True).start()

    def _show_popup(self, selected_text: str) -> None:
        # Close any existing popup
        if self._popup is not None:
            try:
                self._popup.close()
            except Exception:
                pass
            self._popup = None

        from .popup_window import PopupWindow

        source_app = self._get_active_window_title()

        popup = PopupWindow(
            selected_text=selected_text,
            source_app_name=source_app,
            on_paste_back=lambda text: self._paste_back(text),
        )
        popup.set_application(self)
        popup.present()
        GLib.idle_add(popup.focus_followup)
        self._popup = popup

    def _paste_back(self, text: str) -> None:
        from .clipboard_manager import ClipboardManager

        def _do_paste():
            ClipboardManager().paste_text(text)

        threading.Thread(target=_do_paste, daemon=True).start()

    @staticmethod
    def _get_active_window_title() -> str:
        """Best-effort: get the title of the currently focused window."""
        import subprocess
        try:
            result = subprocess.run(
                ["xdotool", "getactivewindow", "getwindowname"],
                capture_output=True, timeout=2,
            )
            if result.returncode == 0:
                return result.stdout.decode("utf-8", errors="replace").strip()
        except Exception:
            pass
        return ""

    # ------------------------------------------------------------------
    # Settings window
    # ------------------------------------------------------------------

    def _open_settings(self) -> None:
        if self._settings_win is not None:
            try:
                self._settings_win.present()
                return
            except Exception:
                self._settings_win = None

        from .settings_store import SettingsStore
        from .keyring_service import KeyringService
        from .settings_window import SettingsWindow

        store = SettingsStore()
        api_key = KeyringService().get_api_key()

        win = SettingsWindow(
            current_settings=store.settings,
            current_api_key=api_key,
            on_save=self._on_settings_saved,
            on_hotkey_reload=self._reload_hotkey,
        )
        win.set_application(self)
        win.connect("close-request", self._on_settings_closed)
        win.present()
        self._settings_win = win

    def _on_settings_closed(self, _win) -> None:
        self._settings_win = None
        return False

    def _on_settings_saved(self, settings_dict: dict, api_key: str) -> None:
        from .settings_store import SettingsStore
        from .keyring_service import KeyringService

        store = SettingsStore()
        for key, value in settings_dict.items():
            store.set(key, value)
        store.save()

        KeyringService().set_api_key(api_key)

    def _reload_hotkey(self, hotkey_str: str) -> None:
        if self._hotkey_manager is not None:
            self._hotkey_manager.reload(hotkey_str)

    # ------------------------------------------------------------------
    # System tray
    # ------------------------------------------------------------------

    def _setup_tray(self) -> None:
        if _tray_backend in ("ayatana", "appindicator"):
            self._setup_appindicator_tray()
        else:
            self._setup_pystray_tray()

    def _setup_appindicator_tray(self) -> None:
        try:
            indicator = AppIndicator.Indicator.new(
                "aihelper",
                "user-available-symbolic",   # theme icon fallback
                AppIndicator.IndicatorCategory.APPLICATION_STATUS,
            )
            # Try to use our SVG icon if installed
            import os
            icon_path = os.path.expanduser(
                "~/.local/share/icons/hicolor/scalable/apps/aihelper.svg"
            )
            if os.path.exists(icon_path):
                indicator.set_icon_full(icon_path, "AIHelper")
            else:
                indicator.set_icon_full("user-available", "AIHelper")

            indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE)

            menu = Gtk.Menu()

            item_settings = Gtk.MenuItem(label="Settings")
            item_settings.connect("activate", lambda _: self._open_settings())
            menu.append(item_settings)

            menu.append(Gtk.SeparatorMenuItem())

            item_quit = Gtk.MenuItem(label="Quit AIHelper")
            item_quit.connect("activate", lambda _: self._quit_app())
            menu.append(item_quit)

            menu.show_all()
            indicator.set_menu(menu)
            self._tray_indicator = indicator
            print("[Tray] AppIndicator tray ready")
        except Exception as exc:
            print(f"[Tray] AppIndicator setup failed: {exc} – falling back to pystray")
            self._setup_pystray_tray()

    def _setup_pystray_tray(self) -> None:
        try:
            import pystray  # type: ignore
            from PIL import Image, ImageDraw  # type: ignore

            # Create a simple icon image
            img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
            draw = ImageDraw.Draw(img)
            draw.ellipse([4, 4, 60, 60], fill=(74, 158, 255, 255))
            draw.text((20, 20), "AI", fill=(255, 255, 255, 255))

            menu = pystray.Menu(
                pystray.MenuItem("Settings", lambda _icon, _item: GLib.idle_add(self._open_settings)),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Quit AIHelper", lambda _icon, _item: GLib.idle_add(self._quit_app)),
            )

            icon = pystray.Icon("aihelper", img, "AIHelper", menu)

            t = threading.Thread(target=icon.run, daemon=True)
            t.start()
            self._tray_pystray = icon
            print("[Tray] pystray tray ready")
        except Exception as exc:
            print(
                f"[Tray] pystray setup failed: {exc}\n"
                "  No tray icon available.  "
                "Install pystray + Pillow: pip install pystray Pillow"
            )

    # ------------------------------------------------------------------
    # Quit
    # ------------------------------------------------------------------

    def _quit_app(self) -> None:
        if self._hotkey_manager is not None:
            try:
                self._hotkey_manager.stop()
            except Exception:
                pass
        if self._tray_pystray is not None:
            try:
                self._tray_pystray.stop()
            except Exception:
                pass
        self.quit()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> int:
    app = AIHelperApp()
    return app.run(sys.argv)
