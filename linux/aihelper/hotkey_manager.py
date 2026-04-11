"""
hotkey_manager.py – global hotkey listener using pynput.

On X11/XWayland this works out of the box.
On native Wayland without XWayland the user must be in the `input` group:
    sudo usermod -aG input $USER
and re-login.
"""

from __future__ import annotations

import threading
from typing import Callable, Optional


class HotkeyManager:
    """Manages a pynput GlobalHotKeys listener for a configurable hotkey."""

    def __init__(self, on_activate: Callable[[], None]) -> None:
        self._on_activate = on_activate
        self._hotkey_str: str = "<ctrl>+<shift>+g"
        self._listener: Optional[object] = None  # pynput.keyboard.GlobalHotKeys
        self._lock = threading.Lock()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def start(self, hotkey_str: Optional[str] = None) -> None:
        """Start (or restart) the listener with the given hotkey string."""
        if hotkey_str:
            self._hotkey_str = hotkey_str
        self._restart()

    def reload(self, new_hotkey_str: str) -> None:
        """Swap the active hotkey at runtime (e.g., after settings save)."""
        self._hotkey_str = new_hotkey_str
        self._restart()

    def stop(self) -> None:
        with self._lock:
            self._stop_listener()

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _restart(self) -> None:
        with self._lock:
            self._stop_listener()
            self._start_listener()

    def _stop_listener(self) -> None:
        if self._listener is not None:
            try:
                self._listener.stop()  # type: ignore[attr-defined]
            except Exception as exc:
                print(f"[HotkeyManager] Error stopping listener: {exc}")
            self._listener = None

    def _start_listener(self) -> None:
        try:
            from pynput import keyboard  # type: ignore

            hotkey_map = {self._hotkey_str: self._fire}
            listener = keyboard.GlobalHotKeys(hotkey_map)
            listener.daemon = True
            listener.start()
            self._listener = listener
            print(f"[HotkeyManager] Listening for hotkey: {self._hotkey_str}")
        except ImportError:
            print(
                "[HotkeyManager] pynput not installed – global hotkey disabled. "
                "Install with: pip install pynput"
            )
        except Exception as exc:
            print(
                f"[HotkeyManager] Failed to start hotkey listener: {exc}\n"
                "  On Wayland without XWayland you may need to:\n"
                "    sudo usermod -aG input $USER  (then re-login)"
            )

    def _fire(self) -> None:
        """Called by pynput on hotkey press – dispatches to GLib main loop."""
        try:
            from gi.repository import GLib  # type: ignore
            GLib.idle_add(self._on_activate)
        except ImportError:
            self._on_activate()
