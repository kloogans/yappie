<p align="center">
  <img src="Yappie/Assets/yappie-logo.png" width="200" alt="Yappie logo" />
</p>

<p align="center" style="text-decoration:none;">
  <strong style="font-size:2em;">Yappie</strong>
</p>

<p align="center">
  Fast, private dictation for macOS. On-device or cloud. Your choice.
</p>

---

Yappie is a menubar app that turns your voice into text. Press a key, speak, and your words appear wherever your cursor is. It runs Whisper models directly on your Mac using Apple Silicon, so your audio never leaves the device. You can also connect cloud APIs as a fallback or primary backend.

> **Looking for the Linux version?** Check out [Yappie for Linux](https://github.com/kloogans/yappie-linux).

## Features

- **On-device transcription** powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) and CoreML. No API keys, no internet, no data leaving your Mac.
- **Cloud API support** for OpenAI, Groq, and any OpenAI-compatible Whisper endpoint.
- **Automatic fallback chain.** Set up multiple backends and Yappie tries them in order. If the primary fails, the next one picks up.
- **Push-to-talk or toggle mode.** Hold a key to record, or click to start and stop.
- **Custom hotkeys.** Use the default Fn key or set any key combination.
- **Auto-paste.** Transcribed text goes straight to your cursor. No Cmd+V needed.
- **Drag-and-drop backend ordering.** Reorder your backends by dragging cards in Preferences.
- **Lazy-loaded fallbacks.** Only your primary model loads at startup. Fallback models load on first use, keeping startup fast.

## Getting Started

### Requirements

- macOS 14 or later
- Apple Silicon (M1 or later) for on-device transcription
- Intel Macs can use cloud API backends only

### Install

**Homebrew (recommended):**

```bash
brew tap kloogans/yappie
brew install --cask yappie
```

**Download:** Grab the latest `.zip` from [Releases](https://github.com/kloogans/yappie/releases), unzip, and drag `Yappie.app` to your Applications folder.

**Build from source:** Requires Xcode and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/kloogans/yappie.git
cd yappie
make build
make run
```

### Permissions

Yappie needs two macOS permissions:

**Microphone.** A system dialog should appear on first launch. If not, go to System Settings > Privacy & Security > Microphone and add Yappie.

**Accessibility.** Required for auto-paste. Go to System Settings > Privacy & Security > Accessibility, click +, and add Yappie. Without this, Yappie will still transcribe but you'll need to paste manually with Cmd+V.

> **Homebrew note:** If macOS blocks the app or permissions aren't working, run `xattr -dr com.apple.quarantine /Applications/Yappie.app` in your terminal, then relaunch.

## How to Use

**Push-to-talk (default):** Hold the Fn key, speak, release. Your words get transcribed and pasted into the active app.

**Toggle mode:** Click the Yappie icon in the menu bar to start recording. Click again to stop and transcribe.

Switch between modes in Preferences > General.

## Backends

Yappie supports three types of transcription backends. Set up one or more in Preferences > Backends.

### On-Device (Local Whisper)

Runs a Whisper model locally on your Mac using Apple Silicon's Neural Engine. No internet required.

To set up:
1. Open Preferences > Backends > Add Backend
2. Select "Local Whisper"
3. Pick a language and model size
4. Download the model

Available models range from Tiny (~40 MB, fastest) to Large v3 (~1.5 GB, most accurate). Yappie recommends a model based on your Mac's RAM. The first launch after download takes longer while CoreML compiles the model for your hardware. Subsequent launches load in under a second.

Your primary local model loads at startup. Fallback local models stay unloaded until needed, so adding multiple models won't slow down your Mac.

### OpenAI-Compatible API

Works with any service that implements the `/v1/audio/transcriptions` endpoint.

| Service | Base URL | API key required |
|---------|----------|-----------------|
| [OpenAI](https://platform.openai.com) | `https://api.openai.com/v1` | Yes |
| [Groq](https://groq.com) | `https://api.groq.com/openai/v1` | Yes |
| [faster-whisper-server](https://github.com/fedirz/faster-whisper-server) | `http://your-server:8000/v1` | No |
| [LocalAI](https://localai.io) | `http://localhost:8080/v1` | No |

API keys are stored in the macOS Keychain.

### Custom TCP

For custom transcription servers that accept raw audio over a TCP socket. Provide a host and port. Yappie sends WAV audio data and reads back UTF-8 text.

Compatible with [Yappie for Linux](https://github.com/kloogans/yappie-linux) and any server that follows the same protocol.

## Preferences

Click the Yappie icon in the menu bar and select Preferences.

### General

| Setting | Options | Default |
|---------|---------|---------|
| Recording mode | Push-to-talk (hold key) / Toggle (click to start/stop) | Push-to-talk |
| Hotkey | Fn key / Custom key combination | Fn |
| After transcription | Copy and paste / Copy to clipboard only | Copy and paste |
| Launch at login | On / Off | Off |

### Backends

Your transcription backends appear as cards. You can:

- **Drag and drop** to reorder priority (top = primary, rest = fallbacks)
- **Enable/disable** individual backends with the toggle
- **Edit** a backend by double-clicking its card
- **Delete** a backend with the trash icon or right-click menu

New local backends are automatically set as the primary.

## Building from Source

```bash
# Build
make build

# Build and run (copies to /Applications, launches, tails debug log)
make run

# Run tests
make test

# Clean build artifacts
make clean

# Deep clean (DerivedData, Launch Services, preference caches)
make deepclean
```

The project uses [xcodegen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`. If you modify the project structure:

```bash
xcodegen generate
```

## License

MIT
