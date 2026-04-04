# Yappie

Fast dictation for macOS. Hold a key, speak, release, and the transcribed text gets pasted into whatever app you're using.

Yappie is a lightweight menubar app that sends audio to a speech-to-text server for transcription. It works with any OpenAI-compatible API (OpenAI, Groq, local Whisper servers) or custom TCP endpoints.

## How it works

1. **Hold Fn** to start recording
2. **Release Fn** to stop and transcribe
3. Text is copied to your clipboard and pasted automatically

Or use **toggle mode**: click the menubar icon to start, click again to stop.

## Requirements

- macOS 14+
- A transcription backend — either:
  - An OpenAI-compatible API endpoint (OpenAI, Groq, local faster-whisper-server, etc.)
  - A custom TCP transcription server

## Install

Clone and build with Xcode:

```bash
git clone https://github.com/kloogans/yappie.git
cd yappie
make build
```

Then open `Yappie.app` from the build output, or:

```bash
make run
```

## Configuration

Open **Preferences** from the menubar icon.

### Backends

Add one or more transcription backends. Yappie tries them in order — if the first fails, it automatically falls back to the next.

**OpenAI-Compatible API** — works with any service implementing the Whisper API format:
- [OpenAI](https://platform.openai.com) — `https://api.openai.com/v1` with your API key
- [Groq](https://groq.com) — `https://api.groq.com/openai/v1` with your API key
- [faster-whisper-server](https://github.com/fedirz/faster-whisper-server) — `http://your-server:8000/v1` (no API key needed)
- Any OpenAI-compatible endpoint

**Custom TCP** — direct socket connection for custom servers like [hypr-dictate](https://github.com/kloogans/hypr-dictate).

### General

- **Recording mode** — Push-to-talk (hold Fn) or toggle
- **After transcription** — Paste automatically or just copy to clipboard
- **Launch at login** — Start Yappie when you log in

## Permissions

Yappie needs two macOS permissions:

- **Microphone** — prompted automatically on first use
- **Accessibility** — needed for auto-paste (System Settings → Privacy & Security → Accessibility)

## License

MIT
