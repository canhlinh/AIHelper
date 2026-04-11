"""
settings_store.py – persist settings to ~/.config/aihelper/settings.json
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, asdict, field
from typing import Optional


DEFAULTS = {
    "provider": "openai",
    "base_url": "https://api.groq.com/openai/v1",
    "model": "meta-llama/llama-4-scout-17b-16e-instruct",
    "enable_thinking": False,
    "translate_vi": True,
    "translate_ko": True,
    "hotkey": "<ctrl>+<shift>+g",
}

_CONFIG_PATH = os.path.expanduser("~/.config/aihelper/settings.json")


@dataclass
class Settings:
    provider: str = "openai"
    base_url: str = "https://api.groq.com/openai/v1"
    model: str = "meta-llama/llama-4-scout-17b-16e-instruct"
    enable_thinking: bool = False
    translate_vi: bool = True
    translate_ko: bool = True
    hotkey: str = "<ctrl>+<shift>+g"


class SettingsStore:
    """Singleton settings store backed by ~/.config/aihelper/settings.json."""

    _instance: Optional["SettingsStore"] = None

    def __new__(cls) -> "SettingsStore":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._settings = Settings()
            cls._instance._load()
        return cls._instance

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    @property
    def settings(self) -> Settings:
        return self._settings

    def get(self, key: str):
        return getattr(self._settings, key, DEFAULTS.get(key))

    def set(self, key: str, value) -> None:
        if hasattr(self._settings, key):
            setattr(self._settings, key, value)

    def save(self) -> None:
        os.makedirs(os.path.dirname(_CONFIG_PATH), exist_ok=True)
        data = asdict(self._settings)
        with open(_CONFIG_PATH, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)

    def reload(self) -> None:
        self._load()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _load(self) -> None:
        if not os.path.exists(_CONFIG_PATH):
            return
        try:
            with open(_CONFIG_PATH, "r", encoding="utf-8") as fh:
                data: dict = json.load(fh)
            for key, default in DEFAULTS.items():
                val = data.get(key, default)
                setattr(self._settings, key, val)
        except Exception as exc:
            print(f"[SettingsStore] Failed to load settings: {exc}")
