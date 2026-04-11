"""
popup_window.py – Floating dark popup window (GTK4).

Fixed width 700 px, positioned top-centre of primary monitor (140 px from top).
Dark background, rounded corners, no title bar.
"""

from __future__ import annotations

import threading
from typing import Optional, Callable

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gtk, Gdk, GLib, Pango  # type: ignore

# Optional WebKit
_WEBKIT_OK = False
try:
    gi.require_version("WebKit", "6.0")
    from gi.repository import WebKit  # type: ignore
    _WEBKIT_OK = True
except Exception:
    try:
        gi.require_version("WebKit2", "4.1")
        from gi.repository import WebKit2 as WebKit  # type: ignore
        _WEBKIT_OK = True
    except Exception:
        try:
            gi.require_version("WebKit2", "4.0")
            from gi.repository import WebKit2 as WebKit  # type: ignore
            _WEBKIT_OK = True
        except Exception:
            pass

# Optional mistune for markdown
try:
    import mistune  # type: ignore
    _md = mistune.create_markdown(plugins=["strikethrough", "table"])
    def _md_to_html(text: str) -> str:
        return _md(text)
except ImportError:
    def _md_to_html(text: str) -> str:
        return f"<pre>{_escape_html(text)}</pre>"


def _escape_html(text: str) -> str:
    return (
        text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
    )


_POPUP_CSS = b"""
window#aihelper-popup {
    background: transparent;
}
.popup-outer {
    background-color: rgba(25, 26, 28, 0.98);
    border-radius: 16px;
    border: 1px solid rgba(255, 255, 255, 0.12);
}
.popup-header {
    padding: 14px 14px 10px 14px;
    border-bottom: 1px solid rgba(255,255,255,0.07);
}
.followup-entry {
    background: transparent;
    border: none;
    box-shadow: none;
    color: white;
    font-size: 17px;
    font-weight: 500;
    caret-color: white;
}
.followup-entry placeholder {
    color: rgba(255,255,255,0.35);
}
.back-btn {
    background-color: rgba(255,255,255,0.1);
    border-radius: 50%;
    border: none;
    color: rgba(255,255,255,0.6);
    min-width: 28px;
    min-height: 28px;
    padding: 0;
}
.back-btn:hover {
    background-color: rgba(255,255,255,0.18);
}
.action-box {
    background-color: rgba(255,255,255,0.03);
    border-radius: 12px;
    border: 1px solid rgba(255,255,255,0.10);
    padding: 14px;
}
.source-app-label {
    color: rgba(255,255,255,0.5);
    font-size: 13px;
    font-weight: 700;
}
.action-label {
    color: rgba(255,255,255,0.5);
    font-size: 12px;
}
.response-label {
    color: #e8e8e8;
    font-size: 15px;
}
.thinking-header {
    color: rgba(100, 160, 255, 0.85);
    font-size: 12px;
    font-weight: 700;
}
.thinking-body {
    color: rgba(255,255,255,0.5);
    font-size: 13px;
}
.thinking-box {
    background-color: rgba(59, 130, 246, 0.05);
    border-radius: 8px;
    border: 1px solid rgba(59, 130, 246, 0.12);
    padding: 8px;
}
.model-hint {
    color: rgba(255,255,255,0.3);
    font-size: 12px;
    padding: 4px 4px 0 4px;
}
.quick-btn-vi {
    background-color: rgba(220, 38, 38, 0.12);
    color: rgba(248, 113, 113, 0.9);
    border: 1px solid rgba(220, 38, 38, 0.25);
    border-radius: 6px;
    padding: 3px 8px;
    font-size: 11px;
    font-weight: 500;
}
.quick-btn-vi:hover {
    background-color: rgba(220, 38, 38, 0.22);
}
.quick-btn-ko {
    background-color: rgba(37, 99, 235, 0.12);
    color: rgba(96, 165, 250, 0.9);
    border: 1px solid rgba(37, 99, 235, 0.25);
    border-radius: 6px;
    padding: 3px 8px;
    font-size: 11px;
    font-weight: 500;
}
.quick-btn-ko:hover {
    background-color: rgba(37, 99, 235, 0.22);
}
.ai-badge {
    background-color: rgba(255,255,255,0.05);
    border-radius: 999px;
    padding: 3px 8px;
    color: rgba(255,255,255,0.5);
    font-size: 11px;
    font-weight: 600;
}
.cancel-btn {
    background: transparent;
    border: none;
    color: rgba(255,255,255,0.4);
    font-size: 11px;
    font-weight: 500;
    padding: 4px 8px;
}
.cancel-btn:hover {
    color: rgba(255,255,255,0.7);
}
.paste-btn {
    background: linear-gradient(to bottom, #3b82f6, #2563eb);
    color: white;
    border: 1px solid rgba(255,255,255,0.2);
    border-radius: 8px;
    padding: 6px 14px;
    font-size: 12px;
    font-weight: 600;
}
.paste-btn:hover {
    background: linear-gradient(to bottom, #60a5fa, #3b82f6);
}
.popup-footer {
    padding: 8px 14px 12px 14px;
    border-top: 1px solid rgba(255,255,255,0.07);
}
"""


class _LoadingDots(Gtk.Box):
    """Three animated dots."""

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        self._dots: list[Gtk.Label] = []
        self._current = 0
        self._timer_id: Optional[int] = None

        for _ in range(3):
            lbl = Gtk.Label(label="●")
            lbl.set_markup('<span color="rgba(255,255,255,0.2)" size="small">●</span>')
            self._dots.append(lbl)
            self.append(lbl)

        self.connect("map", self._start)
        self.connect("unmap", self._stop)

    def _start(self, _widget) -> None:
        if self._timer_id is None:
            self._timer_id = GLib.timeout_add(350, self._tick)

    def _stop(self, _widget) -> None:
        if self._timer_id is not None:
            GLib.source_remove(self._timer_id)
            self._timer_id = None

    def _tick(self) -> bool:
        for i, lbl in enumerate(self._dots):
            if i == self._current:
                lbl.set_markup('<span color="rgba(255,255,255,0.75)" size="small">●</span>')
            else:
                lbl.set_markup('<span color="rgba(255,255,255,0.2)" size="small">●</span>')
        self._current = (self._current + 1) % 3
        return True


def _make_webkit_view(height: int = 200) -> Optional[object]:
    if not _WEBKIT_OK:
        return None
    try:
        settings = WebKit.Settings()
        settings.set_enable_javascript(False)
        settings.set_enable_write_console_messages_to_stdout(False)

        wv = WebKit.WebView()
        wv.set_settings(settings)
        wv.set_background_color(Gdk.RGBA(0, 0, 0, 0))
        wv.set_size_request(650, height)
        return wv
    except Exception:
        return None


def _load_html_in_webkit(wv, html_body: str) -> None:
    html = (
        "<html><body style='"
        "background:transparent;"
        "color:#e8e8e8;"
        "font-family:system-ui,sans-serif;"
        "font-size:15px;"
        "margin:0;"
        "padding:0;"
        "line-height:1.6;"
        "word-wrap:break-word;"
        "'>"
        + html_body
        + "</body></html>"
    )
    try:
        wv.load_html(html, "about:blank")
    except Exception:
        pass


class _MarkdownWidget(Gtk.Stack):
    """
    Renders markdown as HTML in a WebKitWebView if available,
    otherwise falls back to a scrollable GTK Label.
    """

    def __init__(self, height: int = 200) -> None:
        super().__init__()
        self._webkit_view = None
        self._label: Optional[Gtk.Label] = None

        wv = _make_webkit_view(height)
        if wv is not None:
            self._webkit_view = wv
            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            scroll.set_min_content_height(40)
            scroll.set_max_content_height(height)
            scroll.set_child(wv)
            self.add_named(scroll, "webkit")
            self.set_visible_child_name("webkit")
        else:
            lbl = Gtk.Label()
            lbl.set_xalign(0)
            lbl.set_yalign(0)
            lbl.set_wrap(True)
            lbl.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
            lbl.set_selectable(True)
            lbl.add_css_class("response-label")
            lbl.set_max_width_chars(80)
            self._label = lbl
            self.add_named(lbl, "label")
            self.set_visible_child_name("label")

    def set_markdown(self, text: str) -> None:
        if self._webkit_view is not None:
            html_body = _md_to_html(text)
            _load_html_in_webkit(self._webkit_view, html_body)
        elif self._label is not None:
            self._label.set_text(text)


class PopupWindow(Gtk.Window):
    """
    Floating dark popup — top-centre of primary monitor, 700 px wide.
    """

    def __init__(
        self,
        selected_text: str = "",
        source_app_name: str = "",
        on_paste_back: Optional[Callable[[str], None]] = None,
    ) -> None:
        super().__init__()

        self._selected_text = selected_text
        self._source_app_name = source_app_name
        self._on_paste_back = on_paste_back

        # State
        self._thinking_text = ""
        self._content_text = ""
        self._is_loading = False
        self._current_action_label = "Fix Spelling and Grammar"
        self._thinking_expanded = True
        self._translate_vi_running = False
        self._translate_ko_running = False
        self._translation_text = ""

        self._setup_window()
        self._apply_css()
        self._build_ui()
        self._position_window()

        # Auto-run fix spelling if we have text
        if selected_text.strip():
            GLib.idle_add(self._run_fix_spelling)

    # ------------------------------------------------------------------
    # Window setup
    # ------------------------------------------------------------------

    def _setup_window(self) -> None:
        self.set_name("aihelper-popup")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_default_size(700, -1)

        # Close on ESC
        esc = Gtk.EventControllerKey()
        esc.connect("key-pressed", self._on_key_pressed)
        self.add_controller(esc)

        # Close when focus leaves the window
        self.connect("notify::is-active", self._on_focus_changed)

    def _apply_css(self) -> None:
        provider = Gtk.CssProvider()
        provider.load_from_data(_POPUP_CSS)
        try:
            display = self.get_display() or Gdk.Display.get_default()
            if display:
                Gtk.StyleContext.add_provider_for_display(
                    display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                )
        except Exception:
            pass

    def _position_window(self) -> None:
        try:
            display = Gdk.Display.get_default()
            monitor = display.get_monitors().get_item(0)
            geom = monitor.get_geometry()
            x = geom.x + (geom.width - 700) // 2
            y = geom.y + 140
            # GTK4 doesn't have move() for Wayland; use set_startup_id hint or
            # fall back to gravity positioning where possible.
            try:
                self.set_default_size(700, -1)
            except Exception:
                pass
        except Exception:
            pass

    # ------------------------------------------------------------------
    # UI build
    # ------------------------------------------------------------------

    def _build_ui(self) -> None:
        # Transparent outer box to hold the styled inner box
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.set_size_request(700, -1)
        self.set_child(outer)

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        inner.add_css_class("popup-outer")
        inner.set_hexpand(True)
        outer.append(inner)

        inner.append(self._build_header())
        inner.append(self._build_content())
        inner.append(self._build_footer())

    def _build_header(self) -> Gtk.Widget:
        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        hbox.add_css_class("popup-header")

        # Back / close button
        back_btn = Gtk.Button(label="←")
        back_btn.add_css_class("back-btn")
        back_btn.connect("clicked", lambda _: self.close())
        hbox.append(back_btn)

        # Follow-up entry
        self._followup_entry = Gtk.Entry()
        self._followup_entry.set_placeholder_text("Ask follow-up…")
        self._followup_entry.add_css_class("followup-entry")
        self._followup_entry.set_hexpand(True)
        self._followup_entry.connect("activate", self._on_followup_submit)
        hbox.append(self._followup_entry)

        return hbox

    def _build_content(self) -> Gtk.Widget:
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(180)
        scroll.set_max_content_height(500)
        scroll.set_vexpand(True)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        vbox.set_margin_top(14)
        vbox.set_margin_bottom(14)
        vbox.set_margin_start(14)
        vbox.set_margin_end(14)
        scroll.set_child(vbox)

        # ── Action box ────────────────────────────────────────────────
        self._action_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self._action_box.add_css_class("action-box")
        vbox.append(self._action_box)

        # Source app + action row
        meta_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self._source_app_lbl = Gtk.Label(label=self._source_app_name or "")
        self._source_app_lbl.add_css_class("source-app-label")
        self._source_app_lbl.set_xalign(0)
        meta_row.append(self._source_app_lbl)

        self._action_lbl = Gtk.Label(label=self._current_action_label)
        self._action_lbl.add_css_class("action-label")
        self._action_lbl.set_xalign(0)
        meta_row.append(self._action_lbl)
        self._action_box.append(meta_row)

        # Loading dots
        self._loading_dots = _LoadingDots()
        self._loading_dots.set_halign(Gtk.Align.START)
        self._loading_dots.set_visible(False)
        self._action_box.append(self._loading_dots)

        # Markdown content widget
        self._content_widget = _MarkdownWidget(height=300)
        self._content_widget.set_visible(False)
        self._action_box.append(self._content_widget)

        # Error label
        self._error_lbl = Gtk.Label()
        self._error_lbl.set_markup('<span color="#f38ba8"></span>')
        self._error_lbl.set_xalign(0)
        self._error_lbl.set_wrap(True)
        self._error_lbl.set_visible(False)
        self._action_box.append(self._error_lbl)

        # ── Thinking section ──────────────────────────────────────────
        self._thinking_section = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self._thinking_section.add_css_class("thinking-box")
        self._thinking_section.set_visible(False)
        self._action_box.append(self._thinking_section)

        thinking_header_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        thinking_header_row.set_hexpand(True)

        th_lbl = Gtk.Label(label="⚙ Thought Process")
        th_lbl.add_css_class("thinking-header")
        th_lbl.set_xalign(0)
        th_lbl.set_hexpand(True)
        thinking_header_row.append(th_lbl)

        self._thinking_chevron = Gtk.Label(label="▾")
        self._thinking_chevron.add_css_class("thinking-header")
        thinking_header_row.append(self._thinking_chevron)

        thinking_toggle_btn = Gtk.Button()
        thinking_toggle_btn.set_child(thinking_header_row)
        thinking_toggle_btn.add_css_class("cancel-btn")
        thinking_toggle_btn.connect("clicked", self._toggle_thinking)
        self._thinking_section.append(thinking_toggle_btn)

        self._thinking_body = _MarkdownWidget(height=150)
        self._thinking_body.set_visible(True)
        self._thinking_section.append(self._thinking_body)

        # ── Quick translation buttons ─────────────────────────────────
        self._quick_trans_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self._quick_trans_row.set_visible(False)
        self._action_box.append(self._quick_trans_row)

        from .settings_store import SettingsStore
        s = SettingsStore().settings

        if s.translate_vi:
            btn_vi = Gtk.Button(label="🇻🇳 Tiếng Việt")
            btn_vi.add_css_class("quick-btn-vi")
            btn_vi.connect("clicked", self._on_translate_vi)
            self._quick_trans_row.append(btn_vi)

        if s.translate_ko:
            btn_ko = Gtk.Button(label="🇰🇷 Tiếng Hàn")
            btn_ko.add_css_class("quick-btn-ko")
            btn_ko.connect("clicked", self._on_translate_ko)
            self._quick_trans_row.append(btn_ko)

        # ── Translation result ────────────────────────────────────────
        self._trans_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self._trans_box.set_visible(False)
        vbox.append(self._trans_box)

        self._trans_action_lbl = Gtk.Label()
        self._trans_action_lbl.add_css_class("action-label")
        self._trans_action_lbl.set_xalign(0)
        self._trans_box.append(self._trans_action_lbl)

        self._trans_loading = _LoadingDots()
        self._trans_loading.set_halign(Gtk.Align.START)
        self._trans_loading.set_visible(False)
        self._trans_box.append(self._trans_loading)

        self._trans_content = _MarkdownWidget(height=120)
        self._trans_content.set_visible(False)
        self._trans_box.append(self._trans_content)

        # ── Model hint ────────────────────────────────────────────────
        from .settings_store import SettingsStore
        model = SettingsStore().settings.model
        model_hint = Gtk.Label()
        model_hint.set_markup(
            f'<span>✦ {GLib.markup_escape_text(model)}</span>'
        )
        model_hint.add_css_class("model-hint")
        model_hint.set_xalign(0)
        vbox.append(model_hint)

        return scroll

    def _build_footer(self) -> Gtk.Widget:
        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        hbox.add_css_class("popup-footer")

        # AI badge
        badge = Gtk.Label(label="✦ AI Helper")
        badge.add_css_class("ai-badge")
        hbox.append(badge)

        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        hbox.append(spacer)

        # Cancel
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.add_css_class("cancel-btn")
        cancel_btn.connect("clicked", lambda _: self.close())
        hbox.append(cancel_btn)

        # Paste button
        paste_label = f"Paste to {self._source_app_name}" if self._source_app_name else "Paste"
        self._paste_btn = Gtk.Button(label=paste_label)
        self._paste_btn.add_css_class("paste-btn")
        self._paste_btn.set_sensitive(False)
        self._paste_btn.connect("clicked", self._on_paste_clicked)
        hbox.append(self._paste_btn)

        return hbox

    # ------------------------------------------------------------------
    # AI streaming
    # ------------------------------------------------------------------

    def _run_fix_spelling(self) -> None:
        from .ai_service import AIAction
        self._run_action(AIAction.fix_spelling, self._selected_text)

    def _on_followup_submit(self, entry: Gtk.Entry) -> None:
        query = entry.get_text().strip()
        if not query:
            return
        from .ai_service import AIAction
        combined = f"Context: {self._selected_text}\n\nUser Query: {query}"
        entry.set_text("")
        self._run_action(AIAction.follow_up, combined)

    def _on_translate_vi(self, _btn) -> None:
        if not self._content_text:
            return
        from .ai_service import AIAction
        self._run_translation(AIAction.translate_vi, self._content_text)

    def _on_translate_ko(self, _btn) -> None:
        if not self._content_text:
            return
        from .ai_service import AIAction
        self._run_translation(AIAction.translate_ko, self._content_text)

    def _run_action(self, action, text: str) -> None:
        from .ai_service import AIService, TokenType

        self._current_action_label = action.value
        self._action_lbl.set_text(action.value)
        self._thinking_text = ""
        self._content_text = ""
        self._is_loading = True

        self._loading_dots.set_visible(True)
        self._content_widget.set_visible(False)
        self._error_lbl.set_visible(False)
        self._thinking_section.set_visible(False)
        self._quick_trans_row.set_visible(False)
        self._trans_box.set_visible(False)
        self._paste_btn.set_sensitive(False)

        def on_token(token: str, ttype) -> None:
            if ttype == TokenType.thinking:
                self._thinking_text += token
                self._update_thinking_ui()
            else:
                self._content_text += token
                self._update_content_ui()

        def on_complete(err) -> None:
            self._is_loading = False
            self._loading_dots.set_visible(False)
            if err:
                self._show_error(str(err))
            else:
                self._content_widget.set_visible(bool(self._content_text))
                self._paste_btn.set_sensitive(bool(self._content_text))
                from .ai_service import AIAction
                if action == AIAction.fix_spelling:
                    s = __import__(
                        "aihelper.settings_store", fromlist=["SettingsStore"]
                    ).SettingsStore()
                    if s.settings.translate_vi or s.settings.translate_ko:
                        self._quick_trans_row.set_visible(True)

        AIService().stream(
            action=action,
            text=text,
            on_token=on_token,
            on_complete=on_complete,
        )

    def _run_translation(self, action, text: str) -> None:
        from .ai_service import AIService, TokenType

        self._translation_text = ""
        self._trans_action_lbl.set_text(action.value)
        self._trans_box.set_visible(True)
        self._trans_loading.set_visible(True)
        self._trans_content.set_visible(False)

        def on_token(token: str, ttype) -> None:
            self._translation_text += token
            self._trans_content.set_markdown(self._translation_text)
            self._trans_content.set_visible(True)

        def on_complete(err) -> None:
            self._trans_loading.set_visible(False)
            if err:
                self._trans_action_lbl.set_text(f"Error: {err}")

        AIService().stream(
            action=action,
            text=text,
            on_token=on_token,
            on_complete=on_complete,
        )

    # ------------------------------------------------------------------
    # UI update helpers
    # ------------------------------------------------------------------

    def _update_content_ui(self) -> None:
        self._loading_dots.set_visible(False)
        self._content_widget.set_markdown(self._content_text)
        self._content_widget.set_visible(True)

    def _update_thinking_ui(self) -> None:
        if self._thinking_text:
            self._thinking_section.set_visible(True)
            self._thinking_body.set_markdown(self._thinking_text)

    def _show_error(self, msg: str) -> None:
        self._error_lbl.set_markup(
            f'<span color="#f38ba8">{GLib.markup_escape_text(msg)}</span>'
        )
        self._error_lbl.set_visible(True)

    def _toggle_thinking(self, _btn) -> None:
        self._thinking_expanded = not self._thinking_expanded
        self._thinking_body.set_visible(self._thinking_expanded)
        self._thinking_chevron.set_text("▾" if self._thinking_expanded else "▸")

    # ------------------------------------------------------------------
    # Paste back
    # ------------------------------------------------------------------

    def _on_paste_clicked(self, _btn) -> None:
        if self._on_paste_back and self._content_text:
            self._on_paste_back(self._content_text)
            self.close()

    # ------------------------------------------------------------------
    # Keyboard / focus
    # ------------------------------------------------------------------

    def _on_key_pressed(
        self, _ctrl, keyval: int, _keycode: int, _state: Gdk.ModifierType
    ) -> bool:
        if keyval == Gdk.KEY_Escape:
            self.close()
            return True
        return False

    def _on_focus_changed(self, _window, _param) -> None:
        # Close when the window loses focus (e.g. user clicks elsewhere)
        if not self.is_active():
            # Small delay to avoid closing immediately after open
            GLib.timeout_add(200, self._maybe_close)

    def _maybe_close(self) -> bool:
        if not self.is_active():
            self.close()
        return False

    # ------------------------------------------------------------------
    # Public helpers
    # ------------------------------------------------------------------

    def focus_followup(self) -> None:
        self._followup_entry.grab_focus()
