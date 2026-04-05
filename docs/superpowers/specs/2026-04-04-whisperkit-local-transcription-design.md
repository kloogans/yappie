# WhisperKit Local Transcription — Design Spec

**Date:** 2026-04-04
**Status:** Approved
**Branch:** main

## Overview

Add on-device transcription to Yappie via WhisperKit, a Swift package that runs Whisper models locally using CoreML on Apple Silicon. This gives users private, offline transcription with no API keys required, while keeping existing cloud backends as fallback options.

## Scope

- New `LocalBackend` conforming to `TranscriptionBackend`
- Model download and management via `LocalModelManager`
- Wizard UI for selecting and downloading models
- Multilingual support via language selection
- Apple Silicon only (hidden on Intel)

Out of scope: streaming/real-time transcription, model auto-updates, multiple simultaneous local models.

---

## Architecture

### New BackendType

```swift
enum BackendType: String, Codable {
    case api
    case tcp
    case local  // NEW
}
```

### BackendConfig Changes

Add a `language` field to `BackendConfig`:

```swift
struct BackendConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var type: BackendType
    var enabled: Bool
    var baseURL: String?      // API
    var model: String?         // API + Local (model variant name)
    var host: String?          // TCP
    var port: Int?             // TCP
    var language: String?      // Local (nil = auto-detect)
}
```

The `model` field is reused for local backends to store the WhisperKit model variant name (e.g. `"distil-whisper_distil-large-v3_turbo_600MB"`).

### LocalBackend

New file: `Yappie/LocalBackend.swift`

```swift
final class LocalBackend: TranscriptionBackend {
    private let pipe: WhisperKit
    private let language: String?

    init(modelFolder: String, language: String?) async throws
    func transcribe(wavData: Data) async throws -> String
}
```

- Initialized with a path to the downloaded model directory and optional language code
- `transcribe()` writes WAV data to a temp file, calls `pipe.transcribe(audioPath:decodeOptions:)`, cleans up the temp file, and returns the transcribed text
- `DecodingOptions` configured with: `task: .transcribe`, `language: language` (nil for auto-detect), `temperature: 0.0` (greedy decoding for dictation)

### LocalModelManager

New file: `Yappie/LocalModelManager.swift`

Static utility for model lifecycle management:

```swift
enum LocalModelManager {
    static func isAppleSilicon() -> Bool
    static func recommendedModel(ramGB: Int) -> String
    static func modelDirectoryURL() -> URL
    static func downloadedModel() -> String?
    static func download(variant: String, progress: @escaping (Double) -> Void) async throws -> URL
    static func deleteModel() throws
    static func availableModels() async throws -> [String]
}
```

**Model storage:** `~/Library/Application Support/Yappie/Models/`

**Recommendation heuristic:**
- 8 GB RAM → `openai_whisper-small` (~250 MB)
- 16 GB RAM → `distil-whisper_distil-large-v3_turbo_600MB` (~600 MB)
- 24+ GB RAM → `openai_whisper-large-v3_turbo_954MB` (~954 MB)

**`availableModels()`** fetches the full model list from the WhisperKit HuggingFace repo at runtime for the "Browse all models" search.

### BackendManager Changes

The convenience `init(store:)` factory adds a `.local` case:

```swift
case .local:
    if let modelFolder = LocalModelManager.downloadedModel() {
        let backend = try await LocalBackend(
            modelFolder: modelFolder,
            language: config.language
        )
        backends.append(backend)
    }
```

No other changes to BackendManager — the fallback chain, caching, and invalidation all work as-is.

### AppState Changes

`BackendManager` creation becomes async since `LocalBackend` init is async (loads WhisperKit into memory). The `transcribe()` call path in `stopRecording()` already uses `await`, so the manager is created lazily on first transcription if the cache is empty. The Combine sink on `backendStore.$backends` that invalidates the cached manager stays the same — it just nils out `cachedManager`, and the next transcription rebuilds it.

---

## UI Design

### Wizard Step 1: Type Selection

The existing wizard gets reorganized into three sections:

1. **On-Device** — "Local Whisper" card with green accent background, tagline "Private, offline, no API key needed". Only shown on Apple Silicon (`LocalModelManager.isAppleSilicon()`).
2. **Cloud APIs** (renamed from "Quick Setup") — OpenAI, Groq presets. The faster-whisper-server preset is removed.
3. **Custom** — Custom API Endpoint, Custom TCP Socket (unchanged).

The Local Whisper card uses a subtle green gradient background (`linear-gradient`) and green accent text to visually differentiate it from cloud options.

### Wizard Step 2: Model Selection

Shown after clicking "Local Whisper". Contains:

**Language picker** at the top — dropdown defaulting to "Auto-detect" with a hint: "Setting a language improves speed & accuracy". Common languages listed: English, Spanish, French, German, Japanese, Chinese, Korean, Portuguese, Italian, Dutch, plus "Auto-detect".

**5 curated models** displayed as cards with:
- Model name (friendly: "Tiny", "Small", "Distil Large v3 Turbo", "Large v3 Turbo", "Large v3")
- Size badge (e.g. "~600 MB")
- One-line description in plain language
- Accuracy visualization: 1-5 green bars (visual shorthand for quality)
- "RECOMMENDED" badge on the model matching the device's RAM, with green highlight background

| Display Name | Variant | Size | Accuracy Bars |
|---|---|---|---|
| Tiny | `openai_whisper-tiny` | ~40 MB | 1/5 |
| Small | `openai_whisper-small` | ~250 MB | 2/5 |
| Distil Large v3 Turbo | `distil-whisper_distil-large-v3_turbo_600MB` | ~600 MB | 4/5 |
| Large v3 Turbo | `openai_whisper-large-v3_turbo_954MB` | ~954 MB | 4/5 |
| Large v3 | `openai_whisper-large-v3` | ~1.5 GB | 5/5 |

All models are multilingual variants (no `.en` suffixes) to support the language picker.

**"Browse all models..."** link below the curated list:
- Clicking it collapses the curated list to compact mode (dimmed) and reveals a search field
- Search filters all available WhisperKit models from HuggingFace by name, with match highlighting
- Results show full model variant names with sizes
- Selecting a search result behaves the same as picking a curated model

**"Download & Add" button** — disabled until a model is selected. Green accent to match the local theme.

### Wizard Step 3: Download Progress

Centered, focused layout with:

**Downloading state:**
- Yappie tongue mascot (`tongue.svg`) with warm yellow drop shadow
- "Downloading [Model Name]" heading
- "~[size] from Hugging Face" subtitle
- Green progress bar with MB downloaded / total MB and percentage
- Cancel button — cleans up partial download

**Complete state:**
- Yappie sunglasses mascot (`sunglasses.svg`) with warm yellow drop shadow
- "Ready to Go" heading
- Summary card showing: Model, Language, Disk usage
- "Done" button — closes wizard, backend appears in the Backends list

### Backend Card in Preferences

Local backends appear in the Backends tab list with:
- **Icon:** Default Yappie logo (not tongue or sunglasses) — distinguishes from API (globe) and TCP (network) icons
- **Detail line:** `[Model display name] · [Language] · [Disk size]` — same dot-separated pattern as API backends
- **Standard controls:** enable/disable toggle, delete button, double-click/context menu to edit
- **Edit view:** allows changing model (triggers new download, deletes old model) and language

### Mascot SVG Assets

Three Yappie SVGs used across the UI:
- `tongue.svg` — download progress screen (playful "working on it" energy)
- `sunglasses.svg` — download complete screen (confident "we're good" energy)
- Default Yappie logo — backend card icon in Preferences list

Source files at `/Users/jamesobrien/Documents/yappie/`. Copy into Xcode assets.

---

## Data Flow

### Adding a Local Backend

1. User opens Preferences → Backends → Add Backend
2. Wizard shows type selection with "Local Whisper" at top (Apple Silicon only)
3. User clicks Local Whisper → model selection screen
4. User picks language (default: auto-detect) and model (default: recommended for their hardware)
5. User clicks "Download & Add" → download progress screen
6. `LocalModelManager.download(variant:progress:)` downloads model to `~/Library/Application Support/Yappie/Models/`
7. On success → success screen with summary
8. User clicks "Done" → `BackendConfig` created with `type: .local`, `model: variant`, `language: language`, `enabled: true`
9. Config saved via `BackendStore.add()` → Combine sink invalidates cached `BackendManager`

### Transcribing with Local Backend

1. User triggers recording (Fn key or custom hotkey)
2. `AudioRecorder` captures audio, returns WAV data
3. `BackendManager.transcribe(wavData:)` tries backends in order
4. `LocalBackend.transcribe(wavData:)`:
   - Writes WAV data to temp file in `NSTemporaryDirectory()`
   - Calls `pipe.transcribe(audioPath:decodeOptions:)`
   - Deletes temp file
   - Returns transcribed text
5. If `LocalBackend` fails, `BackendManager` falls through to next enabled backend (e.g. Groq API)
6. Result delivered via `TextDelivery`

### Switching Models

1. User double-clicks local backend card → edit view
2. Changes model selection → confirms
3. Old model deleted via `LocalModelManager.deleteModel()`
4. New model downloaded (same progress UI as initial setup)
5. `BackendConfig` updated, `BackendManager` cache invalidated

---

## Dependencies

### WhisperKit Swift Package

- **URL:** `https://github.com/argmaxinc/WhisperKit.git`
- **Version:** `from: "0.9.0"` (compatible with latest v0.18.0)
- **Target:** `WhisperKit` only (not TTSKit or SpeakerKit)
- **Added to:** `project.yml` under packages/dependencies

### Hardware Requirements

- macOS 14.0+ (already the deployment target)
- Apple Silicon (M1/M2/M3/M4) — required for CoreML Neural Engine
- Intel Macs: local backend option hidden entirely from the wizard

---

## Testing

### LocalBackend Unit Tests

New file: `YappieTests/LocalBackendTests.swift`

- Config parsing: correct model variant and language extracted from `BackendConfig`
- Error handling: throws `TranscriptionError` when model not downloaded, when transcription returns empty text
- Temp file cleanup: WAV data temp file cleaned up after transcription (success and failure paths)

### LocalModelManager Unit Tests

New file: `YappieTests/LocalModelManagerTests.swift`

- `recommendedModel(ramGB:)` returns correct variant for 8, 16, 24 GB
- `modelDirectoryURL()` returns expected path under Application Support
- Model directory creation works when directory doesn't exist

### BackendConfig Test Extensions

Extend `YappieTests/BackendConfigTests.swift`:

- Round-trip encode/decode with `.local` type
- `language` field serialization (both set and nil)

### BackendManager Test Extensions

Extend `YappieTests/BackendManagerTests.swift`:

- Local backend participates in fallback chain (using existing `MockBackend` pattern)

### Manual Integration Test

- Add local backend via wizard → download model → record → transcribe → verify text output
- Verify fallback: disable local backend → falls through to cloud API
- Verify model switch: change model in edit view → old model deleted, new downloaded
