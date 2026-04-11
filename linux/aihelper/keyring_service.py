"""
keyring_service.py – secure API key storage via python-keyring
(→ GNOME Secret Service / KWallet depending on desktop environment).
"""

from __future__ import annotations

_SERVICE = "aihelper"
_USERNAME = "api_key"


class KeyringService:
    """Thin wrapper around python-keyring for storing the AI API key."""

    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_api_key(self) -> str:
        """Return the stored API key, or an empty string if not set."""
        try:
            import keyring  # type: ignore
            value = keyring.get_password(_SERVICE, _USERNAME)
            return value or ""
        except Exception as exc:
            print(f"[KeyringService] get_api_key failed: {exc}")
            return ""

    def set_api_key(self, key: str) -> bool:
        """Persist the API key.  Returns True on success."""
        try:
            import keyring  # type: ignore
            if key:
                keyring.set_password(_SERVICE, _USERNAME, key)
            else:
                try:
                    keyring.delete_password(_SERVICE, _USERNAME)
                except Exception:
                    pass
            return True
        except Exception as exc:
            print(f"[KeyringService] set_api_key failed: {exc}")
            return False

    def delete_api_key(self) -> bool:
        """Remove the stored API key.  Returns True on success."""
        try:
            import keyring  # type: ignore
            keyring.delete_password(_SERVICE, _USERNAME)
            return True
        except Exception as exc:
            print(f"[KeyringService] delete_api_key failed: {exc}")
            return False
