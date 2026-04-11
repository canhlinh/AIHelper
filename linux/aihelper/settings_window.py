"""
settings_window.py – GTK4 Settings window (420 px wide).

Provides: provider selector, base URL, model, API key, thinking toggle,
translation toggles, global shortcut recorder, and Save / Cancel buttons.
"""

from __future__ import annotations

from typing import Callable, Optional

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib, Gdk  # type: ignore


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_label(text: str, bold: bool = False, muted: bool = False) -> Gtk.Label:
    lbl = Gtk.Label(label=text)
    lbl.set_xalign(0)
    attrs = []
    if bold:
        attrs.append('<span weight="bold">')
    if muted:
        attrs.append('<span alpha="60%">')
    if attrs:
        lbl.set_markup(
            "".join(attrs) + GLib.markup_escape_text(text) + "".join("</span>" for _ in attrs)
        )
    return lbl


def _section_label(text: str) -> Gtk.Label:
    lbl = Gtk.Label()
    lbl.set_markup(f'<span weight="bold" size="small">{GLib.markup_escape_text(text)}</span>')
    lbl.set_xalign(0)
    lbl.set_margin_top(12)
    lbl.set_margin_bottom(4)
    return lbl


# ---------------------------------------------------------------------------
# SettingsWindow
# ---------------------------------------------------------------------------

class SettingsWindow(Gtk.Window):
    """
    Full settings UI.

    on_save(settings_dict, api_key) is called when the user clicks Save.
    on_hotkey_reload(hotkey_str) is called so main.py can reload the listener.
    """

    def __init__(
        self,
        current_settings,           # Settings dataclass
        current_api_key: str = "",
        on_save: Optional[Callable] = None,
        on_hotkey_reload: Optional[Callable[[str], None]] = None,
        **kwargs,
    ) -> None:
        super().__init__(**kwargs)

        self._on_save = on_save
        self._on_hotkey_reload = on_hotkey_reload
        self._recording_shortcut = False
        self._shortcut_key_controller: Optional[Gtk.EventControllerKey] = None
        self._models_fetching = False

        self.set_title("AIHelper – Settings")
        self.set_default_size(420, -1)
        self.set_resizable(False)
        self.set_modal(True)

        self._apply_css()
        self._build_ui(current_settings, current_api_key)

    # ------------------------------------------------------------------
    # CSS
    # ------------------------------------------------------------------

    def _apply_css(self) -> None:
        css = b"""
        window {
            background-color: #1e1e2e;
            color: #cdd6f4;
        }
        .settings-box {
            padding: 20px;
        }
        .section-frame {
            border-radius: 8px;
            border: 1px solid rgba(255,255,255,0.08);
            background-color: rgba(255,255,255,0.03);
            padding: 12px;
            margin-bottom: 8px;
        }
        entry {
            background-color: rgba(255,255,255,0.06);
            color: #cdd6f4;
            border: 1px solid rgba(255,255,255,0.15);
            border-radius: 6px;
            padding: 6px 10px;
        }
        entry:focus {
            border-color: #89b4fa;
        }
        .shortcut-entry {
            font-family: monospace;
            color: #89b4fa;
        }
        .shortcut-entry.recording {
            border-color: #f38ba8;
            color: #f38ba8;
        }
        button {
            border-radius: 6px;
            padding: 6px 14px;
        }
        .btn-primary {
            background: linear-gradient(to bottom, #3b82f6, #2563eb);
            color: white;
            border: none;
        }
        .btn-primary:hover {
            background: linear-gradient(to bottom, #60a5fa, #3b82f6);
        }
        .btn-secondary {
            background-color: rgba(255,255,255,0.08);
            color: #cdd6f4;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .btn-danger {
            background-color: rgba(243,139,168,0.15);
            color: #f38ba8;
            border: 1px solid rgba(243,139,168,0.3);
        }
        label {
            color: #cdd6f4;
        }
        checkbutton label {
            color: #cdd6f4;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        self.get_style_context().add_provider_for_display(
            self.get_display(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    # ------------------------------------------------------------------
    # UI build
    # ------------------------------------------------------------------

    def _build_ui(self, s, api_key: str) -> None:
        from .ai_service import AIProvider

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(400)
        scroll.set_max_content_height(700)
        self.set_child(scroll)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        outer.add_css_class("settings-box")
        scroll.set_child(outer)

        # ── Provider ──────────────────────────────────────────────────
        outer.append(_section_label("AI Provider"))
        provider_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        provider_box.set_homogeneous(True)

        self._btn_openai = Gtk.ToggleButton(label="OpenAI")
        self._btn_ollama = Gtk.ToggleButton(label="Ollama")
        self._btn_openai.set_group(None)
        self._btn_ollama.set_group(self._btn_openai)

        if s.provider == "openai":
            self._btn_openai.set_active(True)
        else:
            self._btn_ollama.set_active(True)

        self._btn_openai.connect("toggled", self._on_provider_toggled)
        self._btn_ollama.connect("toggled", self._on_provider_toggled)
        provider_box.append(self._btn_openai)
        provider_box.append(self._btn_ollama)
        outer.append(provider_box)

        # ── Connection ────────────────────────────────────────────────
        outer.append(_section_label("Connection"))
        conn_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        conn_frame.add_css_class("section-frame")

        # Base URL
        conn_frame.append(_make_label("Base URL"))
        self._entry_url = Gtk.Entry()
        self._entry_url.set_text(s.base_url)
        self._entry_url.set_placeholder_text("https://api.groq.com/openai/v1")
        conn_frame.append(self._entry_url)

        # Model row
        conn_frame.append(_make_label("Model"))
        model_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self._entry_model = Gtk.Entry()
        self._entry_model.set_text(s.model)
        self._entry_model.set_hexpand(True)
        self._btn_refresh = Gtk.Button(label="⟳ Refresh Models")
        self._btn_refresh.add_css_class("btn-secondary")
        self._btn_refresh.connect("clicked", self._on_refresh_models)
        model_row.append(self._entry_model)
        model_row.append(self._btn_refresh)
        conn_frame.append(model_row)

        # Model dropdown (hidden until refreshed)
        self._model_dropdown = Gtk.DropDown.new_from_strings([])
        self._model_dropdown.set_visible(False)
        self._model_dropdown.connect("notify::selected", self._on_model_selected)
        conn_frame.append(self._model_dropdown)

        outer.append(conn_frame)

        # ── API Key (OpenAI only) ─────────────────────────────────────
        outer.append(_section_label("API Key"))
        self._apikey_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self._apikey_frame.add_css_class("section-frame")

        apikey_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self._entry_apikey = Gtk.PasswordEntry()
        self._entry_apikey.set_text(api_key)
        self._entry_apikey.set_placeholder_text("sk-…")
        self._entry_apikey.set_show_peek_icon(True)
        self._entry_apikey.set_hexpand(True)
        apikey_row.append(self._entry_apikey)
        self._apikey_frame.append(apikey_row)

        hint = _make_label("Stored securely via system keyring", muted=True)
        hint.add_css_class("dim-label")
        self._apikey_frame.append(hint)
        outer.append(self._apikey_frame)

        # ── Ollama Options ────────────────────────────────────────────
        outer.append(_section_label("Options"))
        self._options_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self._options_frame.add_css_class("section-frame")

        self._chk_thinking = Gtk.CheckButton(label="Enable Thinking (experimental reasoning)")
        self._chk_thinking.set_active(s.enable_thinking)
        self._options_frame.append(self._chk_thinking)
        outer.append(self._options_frame)

        # ── Translation ───────────────────────────────────────────────
        outer.append(_section_label("Quick Translation Buttons"))
        trans_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        trans_frame.add_css_class("section-frame")

        self._chk_vi = Gtk.CheckButton(label="Tiếng Việt (Vietnamese)")
        self._chk_vi.set_active(s.translate_vi)
        trans_frame.append(self._chk_vi)

        self._chk_ko = Gtk.CheckButton(label="Tiếng Hàn (Korean)")
        self._chk_ko.set_active(s.translate_ko)
        trans_frame.append(self._chk_ko)
        outer.append(trans_frame)

        # ── Shortcut ──────────────────────────────────────────────────
        outer.append(_section_label("Global Shortcut"))
        shortcut_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        shortcut_frame.add_css_class("section-frame")

        shortcut_hint = _make_label(
            "Click the field below then press your desired key combination.", muted=True
        )
        shortcut_frame.append(shortcut_hint)

        shortcut_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self._entry_shortcut = Gtk.Entry()
        self._entry_shortcut.set_text(self._pynput_to_display(s.hotkey))
        self._entry_shortcut.add_css_class("shortcut-entry")
        self._entry_shortcut.set_editable(False)
        self._entry_shortcut.set_hexpand(True)
        self._entry_shortcut.connect("realize", self._setup_shortcut_capture)
        shortcut_row.append(self._entry_shortcut)

        btn_reset = Gtk.Button(label="Reset")
        btn_reset.add_css_class("btn-danger")
        btn_reset.connect("clicked", self._on_reset_shortcut)
        shortcut_row.append(btn_reset)

        shortcut_frame.append(shortcut_row)
        self._shortcut_raw = s.hotkey  # pynput-format string
        outer.append(shortcut_frame)

        # ── Footer buttons ────────────────────────────────────────────
        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        sep.set_margin_top(12)
        sep.set_margin_bottom(8)
        outer.append(sep)

        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_row.set_halign(Gtk.Align.END)

        btn_cancel = Gtk.Button(label="Cancel")
        btn_cancel.add_css_class("btn-secondary")
        btn_cancel.connect("clicked", lambda _: self.close())

        btn_save = Gtk.Button(label="Save")
        btn_save.add_css_class("btn-primary")
        btn_save.connect("clicked", self._on_save_clicked)

        btn_row.append(btn_cancel)
        btn_row.append(btn_save)
        outer.append(btn_row)

        # Apply initial provider-dependent visibility
        self._update_provider_ui()

    # ------------------------------------------------------------------
    # Event handlers
    # ------------------------------------------------------------------

    def _on_provider_toggled(self, btn: Gtk.ToggleButton) -> None:
        if not btn.get_active():
            return
        self._update_provider_ui()

        from .ai_service import AIProvider
        provider = self._current_provider()
        # Reset URL and model to provider defaults
        self._entry_url.set_text(provider.default_base_url)
        self._entry_model.set_text(provider.default_model)
        # Hide model dropdown
        self._model_dropdown.set_visible(False)

    def _current_provider(self):
        from .ai_service import AIProvider
        return AIProvider.openai if self._btn_openai.get_active() else AIProvider.ollama

    def _update_provider_ui(self) -> None:
        from .ai_service import AIProvider
        is_openai = self._btn_openai.get_active()
        self._apikey_frame.set_visible(is_openai)
        self._chk_thinking.set_sensitive(not is_openai)
        if is_openai:
            self._chk_thinking.set_active(False)

    def _on_refresh_models(self, _btn) -> None:
        if self._models_fetching:
            return
        self._models_fetching = True
        self._btn_refresh.set_label("Fetching…")
        self._btn_refresh.set_sensitive(False)

        provider = self._current_provider()
        base_url = self._entry_url.get_text().strip()
        api_key = self._entry_apikey.get_text().strip()

        import threading
        from .ai_service import AIService

        def _fetch():
            try:
                models = AIService().fetch_models(provider, base_url, api_key)
                GLib.idle_add(self._populate_models, models)
            except Exception as exc:
                GLib.idle_add(self._models_fetch_error, str(exc))

        threading.Thread(target=_fetch, daemon=True).start()

    def _populate_models(self, models: list[str]) -> None:
        self._models_fetching = False
        self._btn_refresh.set_label("⟳ Refresh Models")
        self._btn_refresh.set_sensitive(True)

        if not models:
            return

        store = Gtk.StringList.new(models)
        self._model_dropdown.set_model(store)

        current = self._entry_model.get_text().strip()
        try:
            idx = models.index(current)
            self._model_dropdown.set_selected(idx)
        except ValueError:
            self._model_dropdown.set_selected(0)
            self._entry_model.set_text(models[0])

        self._model_dropdown.set_visible(True)

    def _models_fetch_error(self, msg: str) -> None:
        self._models_fetching = False
        self._btn_refresh.set_label("⟳ Refresh Models")
        self._btn_refresh.set_sensitive(True)
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text="Failed to fetch models",
            secondary_text=msg,
        )
        dialog.connect("response", lambda d, _: d.destroy())
        dialog.present()

    def _on_model_selected(self, dropdown: Gtk.DropDown, _param) -> None:
        item = dropdown.get_selected_item()
        if item:
            self._entry_model.set_text(item.get_string())

    # -- Shortcut recording -------------------------------------------

    def _setup_shortcut_capture(self, widget: Gtk.Entry) -> None:
        ctrl = Gtk.EventControllerKey()
        ctrl.connect("key-pressed", self._on_shortcut_key)
        widget.add_controller(ctrl)
        self._shortcut_key_controller = ctrl

        # Click → start recording
        click = Gtk.GestureClick()
        click.connect("pressed", self._on_shortcut_clicked)
        widget.add_controller(click)

    def _on_shortcut_clicked(self, _gesture, _n, _x, _y) -> None:
        self._recording_shortcut = True
        self._entry_shortcut.set_text("Press key combination…")
        self._entry_shortcut.add_css_class("recording")

    def _on_shortcut_key(
        self, _ctrl, keyval: int, keycode: int, state: Gdk.ModifierType
    ) -> bool:
        if not self._recording_shortcut:
            return False

        # Ignore lone modifier presses
        modifier_keycodes = {
            Gdk.KEY_Control_L, Gdk.KEY_Control_R,
            Gdk.KEY_Shift_L, Gdk.KEY_Shift_R,
            Gdk.KEY_Alt_L, Gdk.KEY_Alt_R,
            Gdk.KEY_Super_L, Gdk.KEY_Super_R,
            Gdk.KEY_Meta_L, Gdk.KEY_Meta_R,
        }
        if keyval in modifier_keycodes:
            return True

        # Build pynput-format string
        parts = []
        if state & Gdk.ModifierType.CONTROL_MASK:
            parts.append("<ctrl>")
        if state & Gdk.ModifierType.SHIFT_MASK:
            parts.append("<shift>")
        if state & Gdk.ModifierType.ALT_MASK:
            parts.append("<alt>")
        if state & Gdk.ModifierType.SUPER_MASK:
            parts.append("<super>")

        key_name = Gdk.keyval_name(keyval) or ""
        if not key_name:
            return True

        # Lowercase single char keys for pynput
        if len(key_name) == 1:
            key_name = key_name.lower()
        else:
            key_name = f"<{key_name.lower()}>"

        parts.append(key_name)
        pynput_str = "+".join(parts)
        self._shortcut_raw = pynput_str
        self._entry_shortcut.set_text(self._pynput_to_display(pynput_str))
        self._entry_shortcut.remove_css_class("recording")
        self._recording_shortcut = False
        return True

    def _on_reset_shortcut(self, _btn) -> None:
        default = "<ctrl>+<shift>+g"
        self._shortcut_raw = default
        self._entry_shortcut.set_text(self._pynput_to_display(default))
        self._entry_shortcut.remove_css_class("recording")
        self._recording_shortcut = False

    # -- Save ---------------------------------------------------------

    def _on_save_clicked(self, _btn) -> None:
        provider = self._current_provider()

        settings_dict = {
            "provider": provider.value,
            "base_url": self._entry_url.get_text().strip() or provider.default_base_url,
            "model": self._entry_model.get_text().strip() or provider.default_model,
            "enable_thinking": self._chk_thinking.get_active(),
            "translate_vi": self._chk_vi.get_active(),
            "translate_ko": self._chk_ko.get_active(),
            "hotkey": self._shortcut_raw,
        }
        api_key = self._entry_apikey.get_text().strip()

        if self._on_save:
            self._on_save(settings_dict, api_key)

        if self._on_hotkey_reload:
            self._on_hotkey_reload(self._shortcut_raw)

        self.close()

    # ------------------------------------------------------------------
    # Utility
    # ------------------------------------------------------------------

    @staticmethod
    def _pynput_to_display(pynput: str) -> str:
        """Convert '<ctrl>+<shift>+g' → 'Ctrl+Shift+G'."""
        mapping = {
            "<ctrl>": "Ctrl",
            "<shift>": "Shift",
            "<alt>": "Alt",
            "<super>": "Super",
            "<cmd>": "Cmd",
            "<meta>": "Meta",
        }
        parts = pynput.split("+")
        display_parts = []
        for p in parts:
            lower = p.lower()
            if lower in mapping:
                display_parts.append(mapping[lower])
            elif lower.startswith("<") and lower.endswith(">"):
                display_parts.append(lower[1:-1].capitalize())
            else:
                display_parts.append(p.upper())
        return "+".join(display_parts)
