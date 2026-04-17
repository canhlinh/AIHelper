use gtk4::prelude::*;
use gtk4::{
    Application, ApplicationWindow, Box as GBox, Button, CssProvider, Entry, Label,
    Orientation, PolicyType, ScrolledWindow, Spinner, Stack, TextView, WrapMode,
    gdk, glib,
};
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;

use crate::ai_service::{stream_ai, AIAction, Token};
use crate::settings::Settings;

/// State shared between the async task and GTK callbacks
#[derive(Default)]
struct PopupState {
    thinking: String,
    content: String,
    done: bool,
}

pub fn show_popup(app: &Application, selected_text: String, settings: Arc<Mutex<Settings>>) {
    let win = ApplicationWindow::builder()
        .application(app)
        .title("AIHelper")
        .default_width(700)
        .default_height(500)
        .decorated(false)
        .resizable(true)
        .build();

    // Dark rounded window via CSS
    let css = CssProvider::new();
    css.load_from_string(POPUP_CSS);
    gtk4::style_context_add_provider_for_display(
        &gdk::Display::default().unwrap(),
        &css,
        gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );

    win.add_css_class("popup-window");

    // ── Root layout ──────────────────────────────────────────────────
    let root = GBox::new(Orientation::Vertical, 0);
    root.add_css_class("popup-root");

    // Header: back button + follow-up entry
    let header = GBox::new(Orientation::Horizontal, 8);
    header.add_css_class("popup-header");

    let back_btn = Button::with_label("←");
    back_btn.add_css_class("back-btn");

    let query_entry = Entry::new();
    query_entry.set_placeholder_text(Some("Ask follow-up..."));
    query_entry.set_hexpand(true);
    query_entry.add_css_class("query-entry");

    header.append(&back_btn);
    header.append(&query_entry);

    // Content area
    let scroll = ScrolledWindow::builder()
        .hscrollbar_policy(PolicyType::Never)
        .vscrollbar_policy(PolicyType::Automatic)
        .vexpand(true)
        .build();

    let content_box = GBox::new(Orientation::Vertical, 12);
    content_box.add_css_class("content-box");

    // Action label
    let action_label = Label::new(Some("Fix Spelling & Grammar"));
    action_label.set_halign(gtk4::Align::Start);
    action_label.add_css_class("action-label");

    // Stack: spinner | result text
    let stack = Stack::new();

    let spinner = Spinner::new();
    spinner.set_spinning(true);
    spinner.add_css_class("spinner");

    let result_view = TextView::new();
    result_view.set_editable(false);
    result_view.set_wrap_mode(WrapMode::Word);
    result_view.set_cursor_visible(false);
    result_view.add_css_class("result-view");

    let thinking_label = Label::new(None);
    thinking_label.set_halign(gtk4::Align::Start);
    thinking_label.set_wrap(true);
    thinking_label.add_css_class("thinking-label");

    let result_col = GBox::new(Orientation::Vertical, 8);
    result_col.append(&thinking_label);
    result_col.append(&result_view);

    stack.add_named(&spinner, Some("loading"));
    stack.add_named(&result_col, Some("result"));
    stack.set_visible_child_name("loading");

    // Translation buttons (shown after fix-spelling completes)
    let trans_box = GBox::new(Orientation::Horizontal, 8);
    trans_box.add_css_class("trans-box");
    trans_box.set_visible(false);

    let btn_vi = Button::with_label("🇻🇳 Tiếng Việt");
    btn_vi.add_css_class("trans-btn");
    let btn_ko = Button::with_label("🇰🇷 Tiếng Hàn");
    btn_ko.add_css_class("trans-btn");
    trans_box.append(&btn_vi);
    trans_box.append(&btn_ko);

    // Translation result
    let trans_view = TextView::new();
    trans_view.set_editable(false);
    trans_view.set_wrap_mode(WrapMode::Word);
    trans_view.set_cursor_visible(false);
    trans_view.add_css_class("trans-view");
    trans_view.set_visible(false);

    content_box.append(&action_label);
    content_box.append(&stack);
    content_box.append(&trans_box);
    content_box.append(&trans_view);
    scroll.set_child(Some(&content_box));

    // Footer
    let footer = GBox::new(Orientation::Horizontal, 8);
    footer.add_css_class("popup-footer");

    let brand = Label::new(Some("✦ AI Helper"));
    brand.add_css_class("brand-label");
    brand.set_hexpand(true);
    brand.set_halign(gtk4::Align::Start);

    let cancel_btn = Button::with_label("Cancel");
    cancel_btn.add_css_class("cancel-btn");

    let paste_btn = Button::with_label("Paste to App  ↵");
    paste_btn.add_css_class("paste-btn");
    paste_btn.set_sensitive(false);

    footer.append(&brand);
    footer.append(&cancel_btn);
    footer.append(&paste_btn);

    root.append(&header);
    root.append(&scroll);
    root.append(&footer);
    win.set_child(Some(&root));

    // ── Shared state ─────────────────────────────────────────────────
    let state = Rc::new(RefCell::new(PopupState::default()));
    let _win_ref = win.clone();

    // Close helpers
    let close = {
        let w = win.clone();
        move || w.close()
    };
    back_btn.connect_clicked({
        let c = close.clone();
        move |_| c()
    });
    cancel_btn.connect_clicked({
        let c = close.clone();
        move |_| c()
    });

    // ESC closes
    let key_ctrl = gtk4::EventControllerKey::new();
    key_ctrl.connect_key_pressed({
        let w = win.clone();
        move |_, key, _, _| {
            if key == gdk::Key::Escape {
                w.close();
                glib::Propagation::Stop
            } else {
                glib::Propagation::Proceed
            }
        }
    });
    win.add_controller(key_ctrl);

    // Paste-back button
    paste_btn.connect_clicked({
        let state = state.clone();
        let w = win.clone();
        move |_| {
            let text = state.borrow().content.clone();
            if text.is_empty() {
                return;
            }
            crate::clipboard::write_clipboard(&text);
            w.close();
            glib::timeout_add_local_once(std::time::Duration::from_millis(400), || {
                crate::clipboard::send_paste();
            });
        }
    });

    // ── Run initial Fix Spelling ──────────────────────────────────────
    run_action(
        AIAction::FixSpelling,
        selected_text.clone(),
        settings.clone(),
        state.clone(),
        stack.clone(),
        result_view.clone(),
        thinking_label.clone(),
        paste_btn.clone(),
        trans_box.clone(),
        trans_view.clone(),
        action_label.clone(),
    );

    // Follow-up on Enter
    query_entry.connect_activate({
        let selected_text = selected_text.clone();
        let settings = settings.clone();
        let state = state.clone();
        let stack = stack.clone();
        let result_view = result_view.clone();
        let thinking_label = thinking_label.clone();
        let paste_btn = paste_btn.clone();
        let trans_box = trans_box.clone();
        let trans_view = trans_view.clone();
        let action_label = action_label.clone();
        move |entry| {
            let query = entry.text().to_string();
            if query.is_empty() {
                return;
            }
            let combined = format!("Context: {selected_text}\n\nUser Query: {query}");
            run_action(
                AIAction::FollowUp,
                combined,
                settings.clone(),
                state.clone(),
                stack.clone(),
                result_view.clone(),
                thinking_label.clone(),
                paste_btn.clone(),
                trans_box.clone(),
                trans_view.clone(),
                action_label.clone(),
            );
        }
    });

    // Translation buttons
    {
        let s = settings.clone();
        let tv = trans_view.clone();
        let result_state = state.clone();
        btn_vi.connect_clicked(move |_| {
            let text = result_state.borrow().content.clone();
            if text.is_empty() { return; }
            run_translation(AIAction::TranslateVI, text, s.clone(), result_state.clone(), tv.clone());
        });
    }
    {
        let s = settings.clone();
        let tv = trans_view.clone();
        let result_state = state.clone();
        btn_ko.connect_clicked(move |_| {
            let text = result_state.borrow().content.clone();
            if text.is_empty() { return; }
            run_translation(AIAction::TranslateKO, text, s.clone(), result_state.clone(), tv.clone());
        });
    }

    // Show translation buttons based on settings
    {
        let cfg = settings.lock().unwrap();
        btn_vi.set_visible(cfg.translate_vi);
        btn_ko.set_visible(cfg.translate_ko);
    }

    win.present();
    query_entry.grab_focus();
}

#[allow(clippy::too_many_arguments)]
fn run_action(
    action: AIAction,
    text: String,
    settings: Arc<Mutex<Settings>>,
    state: Rc<RefCell<PopupState>>,
    stack: Stack,
    result_view: TextView,
    thinking_label: Label,
    paste_btn: Button,
    trans_box: GBox,
    trans_view: TextView,
    action_label: Label,
) {
    action_label.set_text(action.label());
    stack.set_visible_child_name("loading");
    paste_btn.set_sensitive(false);
    trans_box.set_visible(false);
    trans_view.set_visible(false);

    // Clear state
    {
        let mut s = state.borrow_mut();
        s.thinking.clear();
        s.content.clear();
        s.done = false;
    }
    result_view.buffer().set_text("");
    thinking_label.set_text("");

    let (tx, mut rx) = mpsc::unbounded_channel::<Result<Token, String>>();

    let cfg = settings.lock().unwrap().clone();
    let rt = crate::runtime();
    rt.spawn(stream_ai(
        action.clone(),
        text,
        cfg.base_url.clone(),
        cfg.model.clone(),
        cfg.api_key.clone(),
        cfg.enable_thinking,
        tx,
    ));

    let is_fix = action == AIAction::FixSpelling;

    glib::spawn_future_local(async move {
        while let Some(msg) = rx.recv().await {
            match msg {
                Ok(Token::Thinking(t)) => {
                    let mut s = state.borrow_mut();
                    s.thinking.push_str(&t);
                    let text = format!("💭 {}", s.thinking);
                    thinking_label.set_text(&text);
                    stack.set_visible_child_name("result");
                }
                Ok(Token::Content(c)) => {
                    let mut s = state.borrow_mut();
                    s.content.push_str(&c);
                    let buf = result_view.buffer();
                    let mut end = buf.end_iter();
                    buf.insert(&mut end, &c);
                    stack.set_visible_child_name("result");
                }
                Err(e) => {
                    result_view.buffer().set_text(&format!("⚠ Error: {e}"));
                    stack.set_visible_child_name("result");
                    return;
                }
            }
        }
        // Stream finished
        {
            let mut s = state.borrow_mut();
            s.done = true;
        }
        paste_btn.set_sensitive(true);
        if is_fix {
            trans_box.set_visible(true);
        }
    });
}

fn run_translation(
    action: AIAction,
    text: String,
    settings: Arc<Mutex<Settings>>,
    state: Rc<RefCell<PopupState>>,
    trans_view: TextView,
) {
    trans_view.buffer().set_text("");
    trans_view.set_visible(true);
    state.borrow_mut().content.clear();

    let (tx, mut rx) = mpsc::unbounded_channel::<Result<Token, String>>();
    let cfg = settings.lock().unwrap().clone();
    let rt = crate::runtime();
    rt.spawn(stream_ai(
        action,
        text,
        cfg.base_url,
        cfg.model,
        cfg.api_key,
        cfg.enable_thinking,
        tx,
    ));

    glib::spawn_future_local(async move {
        while let Some(msg) = rx.recv().await {
            if let Ok(Token::Content(c)) = msg {
                state.borrow_mut().content.push_str(&c);
                let buf = trans_view.buffer();
                let mut end = buf.end_iter();
                buf.insert(&mut end, &c);
            }
        }
    });
}

const POPUP_CSS: &str = r#"
.popup-root {
    background-color: rgba(26, 26, 28, 0.97);
    border-radius: 16px;
    border: 1px solid rgba(255,255,255,0.12);
}
.popup-header {
    padding: 14px 16px 10px 16px;
    border-bottom: 1px solid rgba(255,255,255,0.08);
}
.back-btn {
    background: rgba(255,255,255,0.08);
    border-radius: 50%;
    border: none;
    color: rgba(255,255,255,0.6);
    min-width: 28px;
    min-height: 28px;
    padding: 0;
    font-size: 14px;
}
.back-btn:hover { background: rgba(255,255,255,0.15); }
.query-entry {
    background: transparent;
    border: none;
    color: white;
    font-size: 17px;
    font-weight: 500;
    box-shadow: none;
    caret-color: white;
}
.query-entry:focus { box-shadow: none; outline: none; }
.content-box {
    padding: 16px;
}
.action-label {
    color: rgba(255,255,255,0.45);
    font-size: 13px;
    font-weight: 700;
}
.result-view {
    background: rgba(255,255,255,0.03);
    color: rgba(255,255,255,0.9);
    font-size: 14px;
    border-radius: 10px;
    padding: 12px;
    border: 1px solid rgba(255,255,255,0.08);
}
.result-view text { background: transparent; }
.thinking-label {
    color: rgba(100,160,255,0.7);
    font-size: 12px;
    font-style: italic;
}
.trans-box { margin-top: 8px; }
.trans-btn {
    background: rgba(255,255,255,0.06);
    color: rgba(255,255,255,0.75);
    border-radius: 8px;
    border: 1px solid rgba(255,255,255,0.12);
    font-size: 12px;
    padding: 4px 10px;
}
.trans-btn:hover { background: rgba(255,255,255,0.12); }
.trans-view {
    background: rgba(255,255,255,0.02);
    color: rgba(255,255,255,0.8);
    font-size: 13px;
    border-radius: 8px;
    padding: 10px;
    border: 1px solid rgba(255,255,255,0.06);
    margin-top: 8px;
}
.trans-view text { background: transparent; }
.popup-footer {
    padding: 8px 16px;
    border-top: 1px solid rgba(255,255,255,0.06);
}
.brand-label {
    color: rgba(255,255,255,0.4);
    font-size: 11px;
    font-weight: 600;
}
.cancel-btn {
    background: transparent;
    border: none;
    color: rgba(255,255,255,0.4);
    font-size: 11px;
}
.cancel-btn:hover { color: rgba(255,255,255,0.7); }
.paste-btn {
    background: linear-gradient(180deg, #3380ff, #4d66e8);
    color: white;
    border-radius: 8px;
    border: 1px solid rgba(255,255,255,0.2);
    font-size: 12px;
    font-weight: 600;
    padding: 5px 12px;
}
.paste-btn:hover { background: linear-gradient(180deg, #4d99ff, #6680ff); }
.paste-btn:disabled { opacity: 0.4; }
.spinner { margin: 20px auto; }
"#;
