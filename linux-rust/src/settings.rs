use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::os::unix::fs::OpenOptionsExt;

fn config_path() -> PathBuf {
    let base = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_default();
            PathBuf::from(home).join(".config")
        });
    base.join("aihelper").join("settings.json")
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    #[serde(default = "default_provider")]
    pub provider: String,
    #[serde(default = "default_base_url")]
    pub base_url: String,
    #[serde(default = "default_model")]
    pub model: String,
    #[serde(skip)]
    pub api_key: String,
    #[serde(default = "default_hotkey")]
    pub hotkey: String,
    #[serde(default = "default_true")]
    pub translate_vi: bool,
    #[serde(default = "default_true")]
    pub translate_ko: bool,
    #[serde(default)]
    pub enable_thinking: bool,
}

fn default_provider() -> String { "OpenAI".into() }
fn default_base_url() -> String { "https://api.groq.com/openai/v1".into() }
fn default_model() -> String { "meta-llama/llama-4-scout-17b-16e-instruct".into() }
fn default_hotkey() -> String { "<Ctrl><Shift>g".into() }
fn default_true() -> bool { true }

impl Default for Settings {
    fn default() -> Self {
        Self {
            provider: default_provider(),
            base_url: default_base_url(),
            model: default_model(),
            api_key: String::new(),
            hotkey: default_hotkey(),
            translate_vi: true,
            translate_ko: true,
            enable_thinking: false,
        }
    }
}

impl Settings {
    pub fn load() -> Self {
        let path = config_path();
        let mut settings: Self = if let Ok(data) = std::fs::read_to_string(&path) {
            serde_json::from_str(&data).unwrap_or_default()
        } else {
            Self::default()
        };
        
        settings.api_key = get_api_key_secret();
        settings
    }

    pub fn save(&self) {
        let path = config_path();
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(json) = serde_json::to_string_pretty(self) {
            let mut options = std::fs::OpenOptions::new();
            options.write(true).create(true).truncate(true).mode(0o600);
            if let Ok(mut file) = options.open(&path) {
                use std::io::Write;
                let _ = file.write_all(json.as_bytes());
            }
        }
        
        set_api_key_secret(&self.api_key);
    }

    pub fn ollama_default_model() -> &'static str {
        "gemma4:e4b"
    }

    pub fn openai_default_base_url() -> &'static str {
        "https://api.groq.com/openai/v1"
    }

    pub fn ollama_default_base_url() -> &'static str {
        "http://localhost:11434/v1"
    }
}

// ── Secure Storage Helpers ───────────────────────────────────────────────────

fn get_schema() -> libsecret::Schema {
    let mut attrs = std::collections::HashMap::new();
    attrs.insert("account", libsecret::SchemaAttributeType::String);
    libsecret::Schema::new(
        "dev.lingcloud.aihelper",
        libsecret::SchemaFlags::NONE,
        attrs,
    )
}

fn get_api_key_secret() -> String {
    let schema = get_schema();
    let mut attrs = std::collections::HashMap::new();
    attrs.insert("account", "aihelper_api_key");
    match libsecret::password_lookup_sync(Some(&schema), attrs, None::<&gio::Cancellable>) {
        Ok(Some(passwd)) => passwd.to_string(),
        _ => String::new(),
    }
}

fn set_api_key_secret(api_key: &str) {
    let schema = get_schema();
    let mut attrs = std::collections::HashMap::new();
    attrs.insert("account", "aihelper_api_key");
    if api_key.trim().is_empty() {
        let _ = libsecret::password_clear_sync(Some(&schema), attrs, None::<&gio::Cancellable>);
    } else {
        let _ = libsecret::password_store_sync(
            Some(&schema),
            attrs,
            Some(libsecret::COLLECTION_DEFAULT),
            "AIHelper API Key",
            api_key,
            None::<&gio::Cancellable>,
        );
    }
}
