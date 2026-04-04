# Multi-Backend Transcription — Design Spec

Yappie currently supports a single hardcoded TCP connection to a Whisper server. This redesign adds support for multiple configurable transcription backends with automatic fallback, making Yappie useful to anyone — not just users with a custom TCP server on their LAN.

## Backend Types

### OpenAI-Compatible API

Standard HTTP endpoint implementing the OpenAI Whisper API format. Covers OpenAI, Groq, Together AI, local servers like faster-whisper-server, LocalAI, and any service implementing `POST /audio/transcriptions`.

Configuration:
- **Name** — user label (e.g. "OpenAI", "Groq", "Local Whisper")
- **Base URL** — e.g. `https://api.openai.com/v1`
- **API Key** — optional (not needed for local servers). Stored in macOS Keychain.
- **Model** — e.g. `whisper-1` (optional, some endpoints auto-select)

### Custom TCP

Raw TCP socket connection — send WAV bytes, receive text. For custom transcription servers.

Configuration:
- **Name** — user label
- **Host** — IP or hostname
- **Port** — port number

## Data Model

```swift
struct BackendConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var type: BackendType  // .api or .tcp
    var enabled: Bool
    // API fields
    var baseURL: String?
    var model: String?
    // TCP fields
    var host: String?
    var port: Int?
    // API key stored separately in Keychain, keyed by id
}
```

Backend configs (minus API keys) stored in UserDefaults as JSON array. Array order defines priority. API keys stored in macOS Keychain keyed by backend UUID.

## Transcription Protocol

Both backend types conform to a shared protocol:

```swift
protocol TranscriptionBackend {
    func transcribe(wavData: Data) async throws -> String
}
```

- **APIBackend:** `POST {baseURL}/audio/transcriptions` with WAV as multipart form data, `Authorization: Bearer {apiKey}` header, model field if configured.
- **TCPBackend:** Send raw WAV bytes, close write end, read UTF-8 response. Same as current `TranscriptionClient`.

## Fallback Chain

When the user finishes recording:

1. Get ordered list of enabled backends
2. Try the first one
3. On failure (connection refused, timeout after 5s, HTTP error), try the next enabled backend
4. If all fail, show macOS notification: "Transcription failed — no backends available"
5. On first fallback in a session, show subtle notification: "Using {backend name}"

`BackendManager` owns the ordered backend list and implements the fallback logic. `AppState` delegates transcription to `BackendManager.transcribe(wavData:)`.

## Preferences Redesign

Tabbed preferences window:

### General Tab

- Recording mode (push-to-talk / toggle)
- After transcription (copy & paste / clipboard only)
- Sound effects toggle
- Launch at login

### Backends Tab

- List of backend cards (expanded card style)
- Each card shows: name, type badge (API/TCP), connection details, masked API key, priority number, enabled/disabled toggle
- Drag to reorder priority
- Click card to edit
- "+ Add Backend" button → two-step wizard
- Delete via edit view

### Add Backend Wizard (two-step)

**Step 1 — Choose type:**
- OpenAI-Compatible API (with description: "Works with OpenAI, Groq, Together AI, local servers...")
- Custom TCP Socket (with description: "Direct TCP connection for custom transcription servers")

**Step 2 — Configure:**
- Type-specific form fields (name, URL/host, API key/port, model)
- "Test Connection" button to verify before saving
- Save / Cancel

## Keychain Storage

API keys stored in macOS Keychain:
- Service: `com.kloogans.Yappie`
- Account: backend UUID string
- Simple wrapper with `save(key:forBackendID:)`, `get(forBackendID:)`, `delete(forBackendID:)`

## Migration

On first launch after update, if old `serverHost`/`serverPort` UserDefaults keys exist:
- Create a TCP backend from them with name "Server"
- Remove old keys
- No action needed if old keys don't exist (fresh install)

## App Icon

Logo SVG at `Yappie/Assets/yappie-logo.svg` — microphone with speech bubble. Used for app icon and can be adapted for menu bar icon.

## File Changes

```
Yappie/
├── AppState.swift              # Modified — uses BackendManager
├── Preferences.swift           # Rewritten — tabbed layout
├── TranscriptionBackend.swift  # New — protocol + BackendManager
├── APIBackend.swift            # New — OpenAI-compatible HTTP
├── TCPBackend.swift            # Renamed from TranscriptionClient.swift
├── BackendConfig.swift         # New — data model, persistence, Keychain
├── BackendWizard.swift         # New — two-step add/edit wizard views
├── Assets/yappie-logo.svg      # New — app logo
├── AudioRecorder.swift         # Unchanged
├── AudioFeedback.swift         # Unchanged
├── WAVEncoder.swift            # Unchanged
├── TextDelivery.swift          # Unchanged
├── HotkeyManager.swift         # Unchanged
├── YappieApp.swift             # Minor changes
├── Sounds/                     # Unchanged
└── Info.plist                  # Unchanged
```
