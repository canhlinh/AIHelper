"""
ai_service.py – AIProvider enum, AIAction enum, AIService streaming class.

Mirrors the logic of the macOS AIService.swift / AIAction Swift enum.
"""

from __future__ import annotations

import threading
from enum import Enum
from typing import Callable, Optional

import requests  # type: ignore


# ---------------------------------------------------------------------------
# Provider
# ---------------------------------------------------------------------------

class AIProvider(str, Enum):
    openai = "openai"
    ollama = "ollama"

    @property
    def default_base_url(self) -> str:
        return {
            AIProvider.openai: "https://api.groq.com/openai/v1",
            AIProvider.ollama: "http://localhost:11434/v1",
        }[self]

    @property
    def default_model(self) -> str:
        return {
            AIProvider.openai: "meta-llama/llama-4-scout-17b-16e-instruct",
            AIProvider.ollama: "gemma4:e4b",
        }[self]

    @property
    def requires_api_key(self) -> bool:
        return self == AIProvider.openai


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

class AIAction(str, Enum):
    fix_spelling = "Fix Spelling and Grammar"
    follow_up = "Follow-up"
    translate_vi = "Dịch sang Tiếng Việt"
    translate_ko = "Dịch sang Tiếng Hàn"

    @property
    def system_prompt(self) -> str:
        return {
            AIAction.fix_spelling: (
                "SYSTEM: You are a robotic grammar correction tool.\n"
                "RULES:\n"
                "- Provide ONLY the corrected text.\n"
                "- NO preamble.\n"
                "- NO explanation.\n"
                "- NO alternatives.\n"
                "- If the input is a fragment, complete it naturally.\n"
                "- Return exactly one string."
            ),
            AIAction.follow_up: (
                "You are a helpful and intelligent assistant. Answer the user's "
                "question or follow-up request accurately based on the provided "
                "text context. Be detailed yet concise."
            ),
            AIAction.translate_vi: (
                "Translate the following text to natural Vietnamese. "
                "Return ONLY the translation. No preamble."
            ),
            AIAction.translate_ko: (
                "Translate the following text to natural Korean. "
                "Return ONLY the translation. No preamble."
            ),
        }[self]

    @property
    def color(self) -> str:
        return {
            AIAction.fix_spelling: "purple",
            AIAction.follow_up: "cyan",
            AIAction.translate_vi: "red",
            AIAction.translate_ko: "blue",
        }[self]

    @property
    def icon_name(self) -> str:
        """GTK icon name."""
        return {
            AIAction.fix_spelling: "tools-check-spelling",
            AIAction.follow_up: "dialog-question",
            AIAction.translate_vi: "accessories-character-map",
            AIAction.translate_ko: "accessories-character-map",
        }[self]


# ---------------------------------------------------------------------------
# Token types
# ---------------------------------------------------------------------------

class TokenType(str, Enum):
    thinking = "thinking"
    content = "content"


# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------

class AIService:
    """Singleton that streams AI completions in a background thread."""

    _instance: Optional["AIService"] = None

    def __new__(cls) -> "AIService":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def stream(
        self,
        action: AIAction,
        text: str,
        on_token: Callable[[str, TokenType], None],
        on_complete: Callable[[Optional[Exception]], None],
        settings=None,
        api_key: str = "",
    ) -> None:
        """
        Run the streaming completion in a background thread.
        on_token / on_complete are called via GLib.idle_add so they are
        safe to update GTK widgets.
        """
        t = threading.Thread(
            target=self._stream_thread,
            args=(action, text, on_token, on_complete, settings, api_key),
            daemon=True,
        )
        t.start()

    def fetch_models(
        self,
        provider: AIProvider,
        base_url: str,
        api_key: str,
    ) -> list[str]:
        """Synchronously fetch model list (call from a background thread)."""
        if provider.requires_api_key and not api_key.strip():
            raise ValueError("API key required for this provider")

        url = base_url.rstrip("/") + "/models"
        headers = {"Content-Type": "application/json"}
        if api_key.strip():
            headers["Authorization"] = f"Bearer {api_key.strip()}"
        headers["User-Agent"] = "AIHelper/1.0"

        resp = requests.get(url, headers=headers, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        return sorted(item["id"] for item in data.get("data", []))

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _stream_thread(
        self,
        action: AIAction,
        text: str,
        on_token: Callable[[str, TokenType], None],
        on_complete: Callable[[Optional[Exception]], None],
        settings,
        api_key: str,
    ) -> None:
        try:
            from gi.repository import GLib  # type: ignore
        except ImportError:
            GLib = None

        def idle(fn, *args):
            if GLib:
                GLib.idle_add(fn, *args)
            else:
                fn(*args)

        try:
            from .settings_store import SettingsStore
            from .keyring_service import KeyringService

            if settings is None:
                store = SettingsStore()
                settings = store.settings

            provider = AIProvider(settings.provider)
            base_url = settings.base_url
            model = settings.model

            if not api_key:
                api_key = KeyringService().get_api_key()

            if provider.requires_api_key and not api_key.strip():
                idle(on_complete, ValueError(
                    "No API key set. Open Settings to add one."
                ))
                return

            url = base_url.rstrip("/") + "/chat/completions"
            headers = {
                "Content-Type": "application/json",
                "Accept": "text/event-stream",
                "User-Agent": "AIHelper/1.0",
            }
            if api_key.strip():
                headers["Authorization"] = f"Bearer {api_key.strip()}"

            body: dict = {
                "model": model,
                "stream": True,
                "messages": [
                    {"role": "system", "content": action.system_prompt},
                    {"role": "user", "content": text},
                ],
            }
            if provider == AIProvider.ollama and settings.enable_thinking:
                body["think"] = True

            resp = requests.post(
                url, json=body, headers=headers, stream=True, timeout=120
            )

            if resp.status_code != 200:
                # Try to parse error JSON
                try:
                    err_json = resp.json()
                    msg = err_json.get("error", {}).get("message", resp.text)
                except Exception:
                    msg = resp.text or f"HTTP {resp.status_code}"
                idle(on_complete, ValueError(f"API Error: {msg}"))
                return

            is_in_think_tag = False

            for raw_line in resp.iter_lines():
                if not raw_line:
                    continue
                if isinstance(raw_line, bytes):
                    raw_line = raw_line.decode("utf-8", errors="replace")

                if not raw_line.startswith("data: "):
                    # Check for bare JSON error
                    try:
                        import json as _json
                        obj = _json.loads(raw_line)
                        if "error" in obj:
                            msg = obj["error"].get("message", str(obj["error"]))
                            idle(on_complete, ValueError(f"API Error: {msg}"))
                            return
                    except Exception:
                        pass
                    continue

                data_str = raw_line[6:]
                if data_str.strip() == "[DONE]":
                    break

                try:
                    import json as _json
                    obj = _json.loads(data_str)
                except Exception:
                    continue

                choices = obj.get("choices", [])
                if not choices:
                    continue
                delta = choices[0].get("delta", {})

                # 1. Explicit reasoning fields
                reasoning = delta.get("reasoning_content") or delta.get("thinking")
                if reasoning:
                    token = reasoning
                    idle(on_token, token, TokenType.thinking)
                    continue

                # 2. Content field (may contain <think> tags)
                content = delta.get("content")
                if not content:
                    continue

                remaining = content
                while remaining:
                    if not is_in_think_tag:
                        idx = remaining.find("<think>")
                        if idx == -1:
                            idle(on_token, remaining, TokenType.content)
                            remaining = ""
                        else:
                            prefix = remaining[:idx]
                            if prefix:
                                idle(on_token, prefix, TokenType.content)
                            is_in_think_tag = True
                            remaining = remaining[idx + len("<think>"):]
                    else:
                        idx = remaining.find("</think>")
                        if idx == -1:
                            idle(on_token, remaining, TokenType.thinking)
                            remaining = ""
                        else:
                            prefix = remaining[:idx]
                            if prefix:
                                idle(on_token, prefix, TokenType.thinking)
                            is_in_think_tag = False
                            remaining = remaining[idx + len("</think>"):]

            idle(on_complete, None)

        except Exception as exc:
            try:
                from gi.repository import GLib  # type: ignore
                GLib.idle_add(on_complete, exc)
            except ImportError:
                on_complete(exc)
