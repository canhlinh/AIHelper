"""
clipboard_manager.py – cross-session clipboard and key-injection helpers.

Supports both X11 (via xdotool + xclip/xsel) and Wayland (via ydotool +
wl-copy/wl-paste).  Falls back gracefully when tools are missing.
"""

from __future__ import annotations

import os
import subprocess
import time
from typing import Optional


def detect_session() -> str:
    """Return 'wayland' or 'x11' based on environment variables."""
    session = os.environ.get("XDG_SESSION_TYPE", "").lower()
    if session == "wayland":
        wayland_display = os.environ.get("WAYLAND_DISPLAY", "")
        if wayland_display:
            return "wayland"
    # WAYLAND_DISPLAY set but XDG_SESSION_TYPE not → probably XWayland
    if os.environ.get("WAYLAND_DISPLAY") and not os.environ.get("DISPLAY"):
        return "wayland"
    return "x11"


class ClipboardManager:
    """Clipboard read/write + key injection for both X11 and Wayland."""

    _instance: Optional["ClipboardManager"] = None

    def __new__(cls) -> "ClipboardManager":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def copy_selection(self) -> str:
        """
        Send Ctrl+C to the focused window (copies current selection),
        waits briefly, then reads and returns the clipboard contents.
        """
        session = detect_session()
        # Small delay so the key release lands before we inject Ctrl+C
        time.sleep(0.08)
        self._send_copy(session)
        time.sleep(0.18)  # allow clipboard to be populated
        return self.get_clipboard(session)

    def paste_text(self, text: str) -> None:
        """Write text to clipboard then send Ctrl+V to the focused window."""
        session = detect_session()
        self.set_clipboard(text, session)
        time.sleep(0.05)
        self._send_paste(session)

    def get_clipboard(self, session: Optional[str] = None) -> str:
        """Read the current clipboard contents."""
        if session is None:
            session = detect_session()

        # First try via GTK (works in both X11 and Wayland inside the same process)
        gtk_text = self._get_clipboard_gtk()
        if gtk_text is not None:
            return gtk_text

        if session == "wayland":
            return self._run(["wl-paste", "--no-newline"], fallback="")
        else:
            # Try xclip first, then xsel as fallback
            text = self._run(["xclip", "-selection", "clipboard", "-o"], fallback=None)
            if text is None:
                text = self._run(["xsel", "--clipboard", "--output"], fallback="")
            return text or ""

    def set_clipboard(self, text: str, session: Optional[str] = None) -> None:
        """Write text to the system clipboard."""
        if session is None:
            session = detect_session()

        # Try via GTK first
        if self._set_clipboard_gtk(text):
            return

        encoded = text.encode("utf-8")
        if session == "wayland":
            self._run_input(["wl-copy"], encoded)
        else:
            # xclip
            ok = self._run_input(["xclip", "-selection", "clipboard"], encoded)
            if not ok:
                self._run_input(["xsel", "--clipboard", "--input"], encoded)

    # ------------------------------------------------------------------
    # Key injection helpers
    # ------------------------------------------------------------------

    def _send_copy(self, session: str) -> None:
        if session == "wayland" and not os.environ.get("DISPLAY"):
            # Pure Wayland – use ydotool
            self._ydotool_key("ctrl+c")
        else:
            self._xdotool_key("ctrl+c")

    def _send_paste(self, session: str) -> None:
        if session == "wayland" and not os.environ.get("DISPLAY"):
            self._ydotool_key("ctrl+v")
        else:
            self._xdotool_key("ctrl+v")

    def _xdotool_key(self, combo: str) -> None:
        try:
            subprocess.run(
                ["xdotool", "key", "--clearmodifiers", combo],
                check=False, capture_output=True, timeout=3,
            )
        except FileNotFoundError:
            print("[ClipboardManager] xdotool not found. Install: dnf install xdotool")
        except Exception as exc:
            print(f"[ClipboardManager] xdotool error: {exc}")

    def _ydotool_key(self, combo: str) -> None:
        """
        Send a key combo via ydotool (Wayland without XWayland).
        Requires ydotoold daemon to be running:
            sudo systemctl start ydotoold
        """
        # Map common combos to ydotool format
        mapping = {
            "ctrl+c": ["29:1", "46:1", "46:0", "29:0"],
            "ctrl+v": ["29:1", "47:1", "47:0", "29:0"],
        }
        keys = mapping.get(combo)
        if keys:
            try:
                subprocess.run(
                    ["ydotool", "key"] + keys,
                    check=False, capture_output=True, timeout=3,
                )
            except FileNotFoundError:
                print("[ClipboardManager] ydotool not found. Install: dnf install ydotool")
            except Exception as exc:
                print(f"[ClipboardManager] ydotool error: {exc}")

    # ------------------------------------------------------------------
    # GTK clipboard helpers (runs inside the GTK process)
    # ------------------------------------------------------------------

    def _get_clipboard_gtk(self) -> Optional[str]:
        try:
            import gi
            gi.require_version("Gdk", "4.0")
            from gi.repository import Gdk, GLib  # type: ignore

            display = Gdk.Display.get_default()
            if display is None:
                return None
            clipboard = display.get_clipboard()

            result: list = [None]
            loop = GLib.MainLoop()

            def _on_text(cb, res):
                try:
                    result[0] = cb.read_text_finish(res)
                except Exception:
                    result[0] = ""
                loop.quit()

            clipboard.read_text_async(None, _on_text)
            # Run loop with a timeout so we don't block forever
            GLib.timeout_add(800, loop.quit)
            loop.run()
            return result[0] or ""
        except Exception:
            return None

    def _set_clipboard_gtk(self, text: str) -> bool:
        try:
            import gi
            gi.require_version("Gdk", "4.0")
            from gi.repository import Gdk, GLib  # type: ignore

            display = Gdk.Display.get_default()
            if display is None:
                return False
            clipboard = display.get_clipboard()
            clipboard.set(text)
            return True
        except Exception:
            return False

    # ------------------------------------------------------------------
    # Subprocess helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _run(cmd: list[str], fallback=None) -> Optional[str]:
        try:
            result = subprocess.run(
                cmd, capture_output=True, timeout=5
            )
            if result.returncode == 0:
                return result.stdout.decode("utf-8", errors="replace")
            return fallback
        except FileNotFoundError:
            return fallback
        except Exception:
            return fallback

    @staticmethod
    def _run_input(cmd: list[str], data: bytes) -> bool:
        try:
            result = subprocess.run(
                cmd, input=data, capture_output=True, timeout=5
            )
            return result.returncode == 0
        except FileNotFoundError:
            return False
        except Exception:
            return False
