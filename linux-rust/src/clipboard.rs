/// Wayland clipboard + key injection via wl-clipboard and ydotool.

use std::process::Command;

fn ydotool(args: &[&str]) {
    // Try user socket first, fall back to system socket
    let socket = if std::path::Path::new("/run/user/1000/.ydotool_socket").exists() {
        "/run/user/1000/.ydotool_socket"
    } else {
        "/tmp/.ydotool_socket"
    };
    let _ = Command::new("ydotool")
        .env("YDOTOOL_SOCKET", socket)
        .args(args)
        .status();
}

/// Read clipboard text — try primary selection first (highlighted text),
/// fall back to clipboard (Ctrl+C copy).
pub fn read_clipboard() -> String {
    // Primary selection = currently highlighted text (no Ctrl+C needed on Wayland)
    let primary = Command::new("wl-paste")
        .args(["--no-newline", "--primary"])
        .output()
        .ok()
        .and_then(|o| if o.status.success() { String::from_utf8(o.stdout).ok() } else { None })
        .unwrap_or_default();

    if !primary.trim().is_empty() {
        return primary;
    }

    // Fall back to regular clipboard
    Command::new("wl-paste")
        .arg("--no-newline")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_default()
}

/// Write text to clipboard via wl-copy.
pub fn write_clipboard(text: &str) {
    let mut child = Command::new("wl-copy")
        .stdin(std::process::Stdio::piped())
        .spawn()
        .expect("wl-copy not found — install wl-clipboard");
    if let Some(stdin) = child.stdin.as_mut() {
        use std::io::Write;
        let _ = stdin.write_all(text.as_bytes());
    }
    let _ = child.wait();
}

/// Paste via Ctrl+V (Linux input keycodes: Ctrl=29, V=47).
pub fn send_paste() {
    ydotool(&["key", "--key-delay", "50", "29:1", "47:1", "47:0", "29:0"]);
}
