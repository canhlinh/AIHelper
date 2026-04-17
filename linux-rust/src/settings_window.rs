use gtk4::prelude::*;
use gtk4::{
    Application, ApplicationWindow, Box as GBox, Button, CheckButton,
    DropDown, Entry, Label, Orientation, PasswordEntry, Separator, Spinner,
    StringList, glib,
};
use std::sync::{Arc, Mutex};
use tokio::sync::oneshot;

use crate::settings::Settings;

/// Convert GTK accel string like `<Ctrl><Shift>g` → `Ctrl+Shift+G`
fn accel_to_label(accel: &str) -> String {
    let s = accel
        .replace("<Ctrl>", "Ctrl+")
        .replace("<Shift>", "Shift+")
        .replace("<Alt>", "Alt+")
        .replace("<Super>", "Super+");
    // Capitalize the final key character
    if let Some((prefix, last)) = s.rsplit_once('+') {
        format!("{}+{}", prefix, last.to_uppercase())
    } else {
        s.to_uppercase()
    }
}

pub fn show_settings(app: &Application, settings: Arc<Mutex<Settings>>, on_save: impl Fn() + 'static) {
    let win = ApplicationWindow::builder()
        .application(app)
        .title("Suano – Settings")
        .default_width(440)
        .resizable(false)
        .build();

    let root = GBox::new(Orientation::Vertical, 16);
    root.set_margin_top(20);
    root.set_margin_bottom(20);
    root.set_margin_start(20);
    root.set_margin_end(20);

    // ── AI Provider ──────────────────────────────────────────────────
    let provider_label = Label::new(Some("AI Provider"));
    provider_label.set_halign(gtk4::Align::Start);

    let provider_list = StringList::new(&["OpenAI", "Ollama"]);
    let provider_combo = DropDown::new(Some(provider_list), gtk4::Expression::NONE);

    let base_url_entry = Entry::new();
    base_url_entry.set_placeholder_text(Some("Base URL"));

    let model_entry = Entry::new();
    model_entry.set_placeholder_text(Some("Model"));

    let fetch_btn = Button::with_label("⟳ Fetch Models");
    let fetch_spinner = Spinner::new();
    fetch_spinner.set_visible(false);

    let model_row = GBox::new(Orientation::Horizontal, 6);
    model_row.append(&model_entry);
    model_row.append(&fetch_btn);
    model_row.append(&fetch_spinner);
    model_entry.set_hexpand(true);

    let api_key_entry = PasswordEntry::new();
    api_key_entry.set_placeholder_text(Some("API Key (sk-...)"));
    api_key_entry.set_show_peek_icon(true);

    let thinking_check = CheckButton::with_label("Enable thinking mode (Ollama only)");

    // Helper: is Ollama selected?
    let is_ollama = || -> bool {
        // DropDown selected index: 0=OpenAI, 1=Ollama
        false // placeholder; we use the selected property below
    };
    let _ = is_ollama; // suppress warning

    // Populate from current settings
    {
        let cfg = settings.lock().unwrap();
        if cfg.provider == "Ollama" {
            provider_combo.set_selected(1);
        } else {
            provider_combo.set_selected(0);
        }
        base_url_entry.set_text(&cfg.base_url);
        model_entry.set_text(&cfg.model);
        api_key_entry.set_text(&cfg.api_key);
        thinking_check.set_active(cfg.enable_thinking);
    }

    // Show/hide API key based on provider
    let update_visibility = {
        let api_key_entry = api_key_entry.clone();
        let thinking_check = thinking_check.clone();
        let combo = provider_combo.clone();
        move || {
            let is_ollama = combo.selected() == 1;
            api_key_entry.set_visible(!is_ollama);
            thinking_check.set_visible(is_ollama);
        }
    };
    update_visibility();

    provider_combo.connect_selected_notify({
        let base_url_entry = base_url_entry.clone();
        let model_entry = model_entry.clone();
        let uv = update_visibility.clone();
        move |combo| {
            let is_ollama = combo.selected() == 1;
            if is_ollama {
                base_url_entry.set_text(Settings::ollama_default_base_url());
                model_entry.set_text(Settings::ollama_default_model());
            } else {
                base_url_entry.set_text(Settings::openai_default_base_url());
                model_entry.set_text("meta-llama/llama-4-scout-17b-16e-instruct");
            }
            uv();
        }
    });

    // Fetch models button
    fetch_btn.connect_clicked({
        let base_url_entry = base_url_entry.clone();
        let model_entry = model_entry.clone();
        let api_key_entry = api_key_entry.clone();
        let fetch_spinner = fetch_spinner.clone();
        let fetch_btn = fetch_btn.clone();
        move |_| {
            let base_url = base_url_entry.text().to_string();
            let api_key = api_key_entry.text().to_string();
            fetch_spinner.set_visible(true);
            fetch_spinner.set_spinning(true);
            fetch_btn.set_sensitive(false);

            let (tx, rx) = oneshot::channel::<Result<Vec<String>, String>>();
            let rt = crate::runtime();
            rt.spawn(async move {
                let result = crate::ai_service::fetch_models(&base_url, &api_key).await;
                let _ = tx.send(result);
            });

            let model_entry = model_entry.clone();
            let fetch_spinner = fetch_spinner.clone();
            let fetch_btn = fetch_btn.clone();
            gtk4::glib::spawn_future_local(async move {
                if let Ok(result) = rx.await {
                    match result {
                        Ok(models) => {
                            let popover = gtk4::Popover::new();
                            popover.set_parent(&fetch_btn);

                            let scrolled_window = gtk4::ScrolledWindow::new();
                            scrolled_window.set_max_content_height(300);
                            scrolled_window.set_policy(gtk4::PolicyType::Never, gtk4::PolicyType::Automatic);

                            let list_box = gtk4::ListBox::new();
                            list_box.set_selection_mode(gtk4::SelectionMode::None);

                            for model in &models {
                                let lbl = gtk4::Label::new(Some(model));
                                lbl.set_halign(gtk4::Align::Start);
                                lbl.set_margin_start(12);
                                lbl.set_margin_end(12);
                                lbl.set_margin_top(8);
                                lbl.set_margin_bottom(8);
                                list_box.append(&lbl);
                            }

                            scrolled_window.set_child(Some(&list_box));
                            popover.set_child(Some(&scrolled_window));

                            let models_clone = models.clone();
                            let model_entry_clone = model_entry.clone();
                            let popover_clone = popover.clone();
                            
                            list_box.connect_row_activated(move |_, row| {
                                let idx = row.index() as usize;
                                if let Some(model_name) = models_clone.get(idx) {
                                    model_entry_clone.set_text(model_name);
                                    popover_clone.popdown();
                                }
                            });

                            popover.popup();
                        }
                        Err(e) => eprintln!("Fetch models error: {e}"),
                    }
                }
                fetch_spinner.set_visible(false);
                fetch_spinner.set_spinning(false);
                fetch_btn.set_sensitive(true);
            });
        }
    });

    // ── Translation ──────────────────────────────────────────────────
    let sep1 = Separator::new(Orientation::Horizontal);

    let trans_label = Label::new(Some("Translation Buttons"));
    trans_label.set_halign(gtk4::Align::Start);

    let vi_check = CheckButton::with_label("Tiếng Việt");
    let ko_check = CheckButton::with_label("Tiếng Hàn");
    {
        let cfg = settings.lock().unwrap();
        vi_check.set_active(cfg.translate_vi);
        ko_check.set_active(cfg.translate_ko);
    }
    let trans_row = GBox::new(Orientation::Horizontal, 20);
    trans_row.append(&vi_check);
    trans_row.append(&ko_check);

    // ── Hotkey ───────────────────────────────────────────────────────
    let sep2 = Separator::new(Orientation::Horizontal);

    let hotkey_label = Label::new(Some("Global Shortcut"));
    hotkey_label.set_halign(gtk4::Align::Start);

    // Press-to-record shortcut button
    let current_hotkey = {
        let cfg = settings.lock().unwrap();
        let hk = cfg.hotkey.clone();
        if hk.is_empty() { "<Ctrl><Shift>g".to_string() } else { hk }
    };
    let hotkey_value = Arc::new(Mutex::new(current_hotkey.clone()));

    let hotkey_btn = Button::with_label(&format!("  {}  ", accel_to_label(&current_hotkey)));
    hotkey_btn.set_tooltip_text(Some("Click, then press your desired shortcut"));

    let recording = Arc::new(std::sync::atomic::AtomicBool::new(false));

    hotkey_btn.connect_clicked({
        let _hotkey_btn = hotkey_btn.clone();
        let recording = recording.clone();
        let hotkey_value = hotkey_value.clone();
        move |btn| {
            if recording.swap(true, std::sync::atomic::Ordering::SeqCst) {
                // Already recording — cancel
                recording.store(false, std::sync::atomic::Ordering::SeqCst);
                let hk = hotkey_value.lock().unwrap().clone();
                btn.set_label(&format!("  {}  ", accel_to_label(&hk)));
                return;
            }
            btn.set_label("  Press shortcut…  ");

            // Capture next key press via EventControllerKey on the button's root window
            let key_ctrl = gtk4::EventControllerKey::new();
            key_ctrl.set_propagation_phase(gtk4::PropagationPhase::Capture);

            let btn2 = btn.clone();
            let recording2 = recording.clone();
            let hotkey_value2 = hotkey_value.clone();
            key_ctrl.connect_key_pressed(move |ctrl, keyval, _keycode, mods| {
                use gtk4::gdk;
                // Ignore bare modifier keys
                let kv = keyval.to_lower();
                if matches!(kv,
                    gdk::Key::Control_L | gdk::Key::Control_R |
                    gdk::Key::Shift_L   | gdk::Key::Shift_R   |
                    gdk::Key::Alt_L     | gdk::Key::Alt_R     |
                    gdk::Key::Super_L   | gdk::Key::Super_R   |
                    gdk::Key::Meta_L    | gdk::Key::Meta_R
                ) {
                    return glib::Propagation::Stop;
                }

                let mut accel = String::new();
                if mods.contains(gdk::ModifierType::CONTROL_MASK) { accel.push_str("<Ctrl>"); }
                if mods.contains(gdk::ModifierType::SHIFT_MASK)   { accel.push_str("<Shift>"); }
                if mods.contains(gdk::ModifierType::ALT_MASK)     { accel.push_str("<Alt>"); }
                if mods.contains(gdk::ModifierType::SUPER_MASK)   { accel.push_str("<Super>"); }
                if let Some(name) = kv.name() { accel.push_str(&name); }

                *hotkey_value2.lock().unwrap() = accel.clone();
                btn2.set_label(&format!("  {}  ", accel_to_label(&accel)));
                recording2.store(false, std::sync::atomic::Ordering::SeqCst);

                // Remove this controller
                if let Some(widget) = ctrl.widget() {
                    widget.remove_controller(ctrl);
                }
                glib::Propagation::Stop
            });

            btn.add_controller(key_ctrl);
        }
    });

    // ── Buttons ───────────────────────────────────────────────────────
    let sep3 = Separator::new(Orientation::Horizontal);

    let btn_row = GBox::new(Orientation::Horizontal, 8);
    btn_row.set_halign(gtk4::Align::End);

    let cancel_btn = Button::with_label("Cancel");
    let save_btn = Button::with_label("Save");
    save_btn.add_css_class("suggested-action");

    btn_row.append(&cancel_btn);
    btn_row.append(&save_btn);

    // Assemble
    root.append(&provider_label);
    root.append(&provider_combo);
    root.append(&base_url_entry);
    root.append(&model_row);
    root.append(&api_key_entry);
    root.append(&thinking_check);
    root.append(&sep1);
    root.append(&trans_label);
    root.append(&trans_row);
    root.append(&sep2);
    root.append(&hotkey_label);
    root.append(&hotkey_btn);
    root.append(&sep3);
    root.append(&btn_row);

    win.set_child(Some(&root));

    cancel_btn.connect_clicked({
        let w = win.clone();
        move |_| w.close()
    });

    save_btn.connect_clicked({
        let w = win.clone();
        let settings = settings.clone();
        move |_| {
            let mut cfg = settings.lock().unwrap();
            cfg.provider = if provider_combo.selected() == 1 {
                "Ollama".into()
            } else {
                "OpenAI".into()
            };
            cfg.base_url = base_url_entry.text().to_string();
            cfg.model = model_entry.text().to_string();
            cfg.api_key = api_key_entry.text().to_string();
            cfg.enable_thinking = thinking_check.is_active();
            cfg.translate_vi = vi_check.is_active();
            cfg.translate_ko = ko_check.is_active();
            cfg.hotkey = hotkey_value.lock().unwrap().clone();
            let new_hotkey = cfg.hotkey.clone();
            cfg.save();
            drop(cfg);
            crate::register_gnome_shortcut(&new_hotkey);
            on_save();
            w.close();
        }
    });

    crate::hotkey_paused().store(true, std::sync::atomic::Ordering::SeqCst);
    win.connect_close_request(|_| {
        crate::hotkey_paused().store(false, std::sync::atomic::Ordering::SeqCst);
        glib::Propagation::Proceed
    });
    win.present();
}
