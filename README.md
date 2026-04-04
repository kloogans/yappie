<p align="center">
  <img src="Yappie/Assets/yappie-logo.png" width="200" alt="Yappie logo" />
</p>

<h1 align="center">Yappie</h1>

<p align="center">
  Fast, local-first dictation for macOS.
</p>

---

Yappie is a small menubar app that records your voice, sends the audio to a speech-to-text backend, and pastes the transcribed text wherever your cursor is. It supports any OpenAI-compatible Whisper API and custom TCP transcription servers, with automatic fallback if your primary backend is unavailable.

> **Looking for the Linux version?** Check out [Yappie for Linux](https://github.com/kloogans/yappie-linux).

## Getting started

### Requirements

- macOS 14 or later
- Xcode (for building from source)
- At least one transcription backend (see [Backends](#backends) below)

### Install

```bash
git clone https://github.com/kloogans/yappie.git
cd yappie
make build
```

To launch the app after building:

```bash
make run
```

You can also open the built `Yappie.app` directly from `~/Library/Developer/Xcode/DerivedData/`.

### Permissions

On first launch, macOS will ask for two permissions:

- **Microphone** - you'll get a system dialog automatically
- **Accessibility** - needed for the auto-paste feature. Go to System Settings > Privacy & Security > Accessibility and add Yappie

If you skip the Accessibility permission, Yappie will still work but you'll need to paste manually with Cmd+V.

## How to use

**Push-to-talk (default):** Hold the Fn key, speak, then release. Your speech gets transcribed and pasted into the focused app.

**Toggle mode:** Click the Yappie icon in the menu bar to start recording, click again to stop and transcribe.

You can switch between these modes in Preferences.

## Backends

Yappie needs a transcription backend to convert your audio to text. You can configure one or more backends in Preferences > Backends. If you set up multiple backends, Yappie will try them in order and fall back to the next one if the first is unreachable.

### OpenAI-compatible API

Works with any service that implements the `/v1/audio/transcriptions` endpoint. Some examples:

| Service | Base URL | API key required |
|---------|----------|-----------------|
| [OpenAI](https://platform.openai.com) | `https://api.openai.com/v1` | Yes |
| [Groq](https://groq.com) | `https://api.groq.com/openai/v1` | Yes |
| [faster-whisper-server](https://github.com/fedirz/faster-whisper-server) | `http://your-server:8000/v1` | No |
| [LocalAI](https://localai.io) | `http://localhost:8080/v1` | No |

To add one, open Preferences > Backends > Add Backend > OpenAI-Compatible API, then fill in the base URL, API key (if needed), and model name.

API keys are stored in the macOS Keychain, not in plaintext config files.

### Custom TCP

For custom transcription servers that accept raw audio over a TCP socket. You provide a host and port. Yappie sends the WAV audio data over the connection and reads back the transcribed text.

This works with servers like [hypr-dictate](https://github.com/kloogans/hypr-dictate) and anything else that follows the same simple protocol: receive WAV bytes, respond with UTF-8 text.

## Preferences

Access preferences by clicking the Yappie icon in the menu bar and selecting Preferences.

### General

| Setting | Options | Default |
|---------|---------|---------|
| Recording mode | Push-to-talk (hold Fn) / Toggle (click to start/stop) | Push-to-talk |
| After transcription | Copy and paste / Copy to clipboard only | Copy and paste |
| Launch at login | On / Off | Off |

### Backends

Your configured transcription backends are shown as cards. You can:

- **Reorder** them to set priority (top = primary, rest = fallbacks)
- **Enable/disable** individual backends with the toggle
- **Delete** a backend by right-clicking its card
- **Add** new backends with the Add Backend button

## Building from source

```bash
# Build
make build

# Run
make run

# Run tests
make test

# Clean
make clean
```

The project uses [xcodegen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`. If you modify the project structure, regenerate with:

```bash
xcodegen generate
```

## License

MIT
