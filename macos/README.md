# AIHelper — macOS

A sleek, lightweight macOS menu bar utility that brings powerful AI writing assistance to any application.

## Prerequisites

- macOS 13.0 or later.
- An OpenAI API key **OR** Ollama running locally.

## Build from Source

1. Open your terminal and clone the repository if you haven't already:
   ```bash
   git clone https://github.com/canhlinh/AIHelper.git
   ```
2. Navigate to the `macos` directory:
   ```bash
   cd AIHelper/macos
   ```
3. Build and Install using the provided Makefile:
   ```bash
   make install
   ```

## Configuration

1. **Accessibility Permissions:** AIHelper requires Accessibility permissions to listen for the global hotkey and interact with other apps.
2. **AI Provider:** Click the menu bar icon (text bubble) → **Settings** to configure your OpenAI API Key or Ollama Base URL.
3. **Shortcut:** Change the global trigger shortcut in the Settings window (default is `⌘⇧G`).
