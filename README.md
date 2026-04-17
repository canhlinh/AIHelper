<p align="center">
  <img src="macos/Screenshots/app_icon.png" width="128" height="128" alt="AIHelper Icon">
</p>

# AIHelper

**AIHelper** is a sleek, lightweight utility for macOS and Linux that brings powerful AI writing assistance to any application. Just select text, press a global hotkey, and let AI fix your grammar, rephrase, or answer follow-up questions.

![AIHelper Screenshot](macos/Screenshots/main_popup.png)

## Available Platforms

This repository contains native native implementations for both macOS and Linux:

- **🍎 [macOS (Swift)](macos/README.md)**: A native macOS menu bar utility built with AppKit and SwiftUI.
- **🐧 [Linux (Rust + GTK4)](linux-rust/README.md)**: A Wayland port for Linux, built with Rust and GTK4.

## Features

- **Global Hotkey:** Trigger the AI assistant instantly from any app (e.g., `⌘⇧G` on macOS, `<Ctrl><Shift>G` on Linux).
- **AI Writing Assistance:** Fix spelling, grammar, and improve clarity.
- **Follow-up Chat:** Ask the AI questions about your selected text context.
- **Paste Back:** Instantly paste the AI's response back into your source application.
- **Customizable:** Works with **OpenAI** (GPT-4o, etc) and **Ollama** (Llama 3, Gemma, etc).

## Installation & Configuration

Because there are distinct native implementations for macOS and Linux, please see the specific instructions in each specialized subdirectory:

- **macOS:** See the [macOS Instructions](macos/README.md).
- **Linux:** See the [Linux Instructions](linux-rust/README.md).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
