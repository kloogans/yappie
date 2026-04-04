# Yappie

Fast dictation for macOS. Hold a key, speak, release, and the transcribed text gets pasted into whatever app you're using.

Yappie is a lightweight menubar app that sends audio to a remote [Whisper](https://github.com/openai/whisper) server for transcription. The model runs on your GPU-equipped machine, so transcriptions are fast and free.

Designed as a macOS companion to [hypr-dictate](https://github.com/kloogans/hypr-dictate), which provides the same workflow on Hyprland/Linux.

## How it works

1. **Hold Fn** to start recording
2. **Release Fn** to stop and transcribe
3. Text is copied to your clipboard and pasted automatically

Or use **toggle mode**: click the menubar icon to start, click again to stop.

## Requirements

- macOS 14+
- A running [hypr-dictate-server](https://github.com/kloogans/hypr-dictate) instance with TCP enabled (port 9876 by default)

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

Open **Preferences** from the menubar icon:

- **Server** — IP and port of your hypr-dictate-server
- **Recording mode** — Push-to-talk (hold Fn) or toggle
- **After transcription** — Paste automatically or just copy to clipboard
- **Launch at login** — Start Yappie when you log in

## Permissions

Yappie needs two macOS permissions:

- **Microphone** — prompted automatically on first use
- **Accessibility** — needed for auto-paste (System Settings → Privacy & Security → Accessibility)

## Server setup

Yappie connects to [hypr-dictate-server](https://github.com/kloogans/hypr-dictate)'s TCP interface. Install hypr-dictate on a machine with a GPU, then make sure the server is running and accessible on your network.

The server listens on port 9876 by default. You can change this in `~/.config/hypr-dictate/config` on the server machine:

```bash
TCP_PORT=9876
```

## License

MIT
