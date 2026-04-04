# Yappie — Design Spec

A native macOS menubar app that sends audio to a remote Whisper server for transcription.

Companion to [hypr-dictate](https://github.com/kloogans/hypr-dictate), which provides the same workflow on Hyprland/Linux. Yappie connects to hypr-dictate-server's TCP interface — the model stays loaded on the remote GPU so transcriptions are fast.

## Core Interaction

Two recording modes:

- **Push-to-talk (default):** Hold Fn, speak, release Fn to transcribe.
- **Toggle:** Click the menubar icon (or press a configurable hotkey) to start recording. Click/press again to stop and transcribe.

## Menubar UI

- **Idle:** Microphone icon in the menu bar.
- **Recording:** Red/pulsing mic icon with elapsed time.
- **Transcribing:** Spinner or activity indicator while waiting for the server response.
- **Menu items:** Start/Stop Recording, Preferences, Quit.

## Audio Pipeline

1. Record from the default input device using `AVAudioEngine`.
2. Capture at 16 kHz mono, output as WAV.
3. On stop: open a TCP socket to the configured server, send the raw WAV bytes, then close the write end of the socket.
4. Read back transcribed text as UTF-8.
5. Deliver text based on user preference (see below).

## Text Delivery

Configurable in Preferences:

- **Clipboard + auto-paste (default):** Copies text to the clipboard and simulates Cmd+V via `CGEvent`.
- **Clipboard only:** Copies text to the clipboard; user pastes manually.

Auto-paste requires macOS Accessibility permissions.

## Configuration

Stored in standard macOS `UserDefaults` (plist). Exposed via a Preferences window:

| Setting | Default | Description |
|---|---|---|
| Server host | `192.168.4.24` | IP or hostname of the hypr-dictate-server |
| Server port | `9876` | TCP port |
| Recording mode | Push-to-talk | Push-to-talk (hold Fn) or toggle |
| Hotkey | Fn | Configurable global hotkey |
| Text delivery | Clipboard + auto-paste | Auto-paste or clipboard only |
| Launch at login | Off | Add to login items |

## Permissions Required

- **Microphone** — audio recording (`AVAudioEngine`).
- **Accessibility** — simulated paste via `CGEvent` (only needed if auto-paste is enabled).

## Project Structure

```
yappie/
├── README.md
├── LICENSE (MIT)
├── Yappie/
│   ├── YappieApp.swift            # App entry point, menubar setup
│   ├── MenuBarController.swift    # Menu bar icon, menu items, status
│   ├── AudioRecorder.swift        # AVAudioEngine, 16kHz mono WAV capture
│   ├── TranscriptionClient.swift  # TCP socket connection to server
│   ├── TextDelivery.swift         # Clipboard + optional Cmd+V paste
│   ├── HotkeyManager.swift        # Global hotkey / Fn key handling
│   ├── Preferences.swift          # Settings window + UserDefaults
│   ├── Assets.xcassets/           # Menu bar icons (idle, recording, transcribing)
│   └── Info.plist
├── Yappie.xcodeproj/
└── .gitignore
```

## Server Protocol

The hypr-dictate-server TCP interface is simple:

1. Connect to `host:port` via TCP.
2. Send the entire WAV file as raw bytes.
3. Close the write end of the socket (half-close).
4. Read the response — UTF-8 transcribed text, or `ERROR:<message>` on failure.
5. Close the connection.

No HTTP, no headers, no framing. Just bytes in, text out.

## Distribution

Single `.app` bundle. Clone and build with Xcode, or download a release binary from GitHub Releases. No Homebrew or package manager initially.

## License

MIT — matches hypr-dictate.
