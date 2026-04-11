# AIHelper – Linux (Fedora 43)

A Linux/Fedora 43 port of the macOS menu-bar AI writing assistant **AIHelper**. It sits in your system tray, listens for a global hotkey, captures your selected text, and shows a floating dark popup with AI-powered writing actions (spell-fix, follow-up Q&A, translation).

---

## Features

- **System tray icon** with Settings and Quit menu items
- **Global hotkey** `Ctrl+Shift+G` (configurable) — captures selected text and opens the popup
- **Floating dark popup** (no title bar, dark background, rounded corners)
  - Follow-up text field, back/close button
  - Scrollable content area with AI response rendered as Markdown (via WebKit2GTK)
  - Collapsible "Thought Process" section for reasoning models
  - Quick translation buttons (Tiếng Việt 🇻🇳, Tiếng Hàn 🇰🇷)
  - AI model hint line at the bottom
  - Footer with "✦ AI Helper" badge, Cancel button, and "Paste to \<app\>" button
- **AI actions**: Fix Spelling & Grammar (auto-run on open), Follow-up, Translate VI, Translate KO
- **Streaming AI responses** (OpenAI-compatible SSE) with `<think>` tag and `reasoning_content`/`thinking` delta field support
- **Paste back**: writes result to clipboard and sends `Ctrl+V` to the source window
- **Settings window** (420 px wide):
  - Provider picker: OpenAI / Ollama
  - Base URL, Model, API Key fields
  - "Refresh Models" button
  - Thinking toggle (Ollama only)
  - Translation toggles
  - Global shortcut recorder
- **Secure API key storage** via `python-keyring` → GNOME Secret Service / KWallet
- **Settings persistence** in `~/.config/aihelper/settings.json`

---

## Prerequisites

### System packages (Fedora 43)

```bash
sudo dnf install -y \
  python3 python3-pip python3-gobject python3-gobject-devel \
  gtk4 gtk4-devel \
  libappindicator-gtk3 libayatana-appindicator \
  webkit2gtk4.1 webkit2gtk4.1-devel \
  xdotool wl-clipboard ydotool \
  libsecret gnome-keyring \
  python3-keyring
```

### Python packages

```bash
pip install --user pynput keyring requests mistune pystray Pillow
```

---

## Installation

```bash
cd linux/
chmod +x install.sh
./install.sh
```

`install.sh` installs system dependencies, pip packages, the `.desktop` file, and creates a launcher symlink in `~/.local/bin/aihelper`.

---

## Running manually

```bash
python3 linux/aihelper.py
```

Or, after installation:

```bash
aihelper
```

---

## Usage

1. Start AIHelper (it appears in the system tray as a chat-bubble icon).
2. Select any text in any application.
3. Press **Ctrl+Shift+G** (default hotkey).
4. The floating popup opens with the selected text already being processed (Fix Spelling & Grammar).
5. Read the result, optionally ask a follow-up question, or click one of the translation buttons.
6. Click **Paste to \<app\>** to write the corrected text back into the source window.
7. Right-click the tray icon → **Settings** to configure the AI provider, model, API key, and hotkey.

---

## Wayland vs X11

| Feature | X11 / XWayland | Native Wayland |
|---|---|---|
| Global hotkey (`pynput`) | ✅ Works | ⚠️ Requires `input` group or root (see below) |
| Copy selection (`xdotool`) | ✅ Works | ❌ Use `ydotool` (needs `ydotoold` running) |
| Paste back (`xdotool`) | ✅ Works | ❌ Use `ydotool` |

### Wayland setup (if not using XWayland)

```bash
# Add yourself to the input group for pynput
sudo usermod -aG input $USER
# (Re-login required)

# Start ydotoold (needed for ydotool key injection)
sudo systemctl enable --now ydotoold
```

Most Fedora 43 desktops run XWayland by default when legacy X11 apps are active, so `xdotool` usually works without extra setup.

---

## Configuration

Settings are stored in `~/.config/aihelper/settings.json`. You can edit this file directly or use the Settings window.

| Key | Default | Description |
|---|---|---|
| `provider` | `openai` | `openai` or `ollama` |
| `base_url` | `https://api.groq.com/openai/v1` | OpenAI-compatible API base URL |
| `model` | `meta-llama/llama-4-scout-17b-16e-instruct` | Model name |
| `enable_thinking` | `false` | Enable reasoning (Ollama only) |
| `translate_vi` | `true` | Show Vietnamese translation button |
| `translate_ko` | `true` | Show Korean translation button |
| `hotkey` | `<ctrl>+<shift>+g` | pynput hotkey string |

The API key is stored securely via `keyring` (GNOME Secret Service / KWallet) and is **not** written to the JSON file.
