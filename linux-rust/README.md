# AIHelper — Linux (Rust + GTK4)

A Fedora Linux/Wayland port of the macOS AIHelper app. Select text in any app, press **Ctrl+Shift+G**, and get instant AI writing assistance.

## Features

- Global hotkey (default `Ctrl+Shift+G`) via GNOME Custom Keybindings & local D-Bus
- Streaming AI responses (OpenAI-compatible APIs + Ollama)
- Follow-up chat in the popup
- `<think>` / reasoning token display (collapsible)
- Translation buttons (Vietnamese / Korean) after grammar fix
- Read/Paste-back background results to source app via `wl-clipboard` and `ydotool`
- Settings persisted to `~/.config/aihelper/settings.json`

## Prerequisites

```bash
# Fedora
sudo dnf install gtk4-devel libsecret-devel glib2-devel dbus-devel wl-clipboard ydotool
```

Rust toolchain: https://rustup.rs

## Build & Install

```bash
./install.sh
```

Or manually:

```bash
cargo build --release
./target/release/aihelper
```

## Configuration

Click the system tray icon → **Settings** to set:

- AI Provider: **OpenAI** (any OpenAI-compatible endpoint, e.g. Groq) or **Ollama**
- Base URL, Model, API Key
- Global shortcut (click to record your desired combination)
- Translation language buttons

## Notes

- Designed for a **GNOME Wayland** session (specifically uses GNOME Settings Daemon for custom keybindings and Wayland clipboard utilities).
- `ydotool` the background daemon must be enabled. `install.sh` handles this for you automatically.
