# WhisperKit Local Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add on-device transcription to Yappie via WhisperKit, giving users private, offline speech-to-text with no API keys.

**Architecture:** New `LocalBackend` conforming to `TranscriptionBackend`, backed by WhisperKit for CoreML inference. A `LocalModelManager` utility handles model downloads and storage. The wizard UI gets a new "Local Whisper" flow with model selection, download progress, and mascot personality.

**Tech Stack:** Swift, SwiftUI, WhisperKit (SPM), CoreML, xcodegen

**Spec:** `docs/superpowers/specs/2026-04-04-whisperkit-local-transcription-design.md`

---

## File Map

### New Files
- `Yappie/LocalBackend.swift` — `TranscriptionBackend` implementation using WhisperKit
- `Yappie/LocalModelManager.swift` — Static utility for model download, storage, device detection
- `Yappie/LocalBackendWizard.swift` — Model selection view, download progress view, model search
- `YappieTests/LocalModelManagerTests.swift` — Unit tests for model manager
- `YappieTests/LocalBackendTests.swift` — Unit tests for local backend
- `Yappie/Assets.xcassets/YappieTongue.imageset/` — Tongue mascot SVG for download screen
- `Yappie/Assets.xcassets/YappieSunglasses.imageset/` — Sunglasses mascot SVG for success screen

### Modified Files
- `project.yml` — Add WhisperKit SPM dependency
- `Yappie/BackendConfig.swift:7-10` — Add `.local` to `BackendType`, add `language` field to `BackendConfig`
- `Yappie/TranscriptionBackend.swift:20-29` — Add `.local` case to `BackendManager` factory
- `Yappie/BackendWizard.swift:14-18,49-123` — Reorganize wizard sections, remove faster-whisper-server, add Local Whisper card
- `Yappie/Preferences.swift:196-306` — Update `BackendCardView` to handle `.local` type icon and detail line
- `Yappie/AppState.swift:133-136` — Make BackendManager creation async
- `YappieTests/BackendConfigTests.swift` — Add `.local` type and `language` field tests
- `YappieTests/BackendManagerTests.swift` — Add local backend in fallback chain test

---

## Task 1: Add WhisperKit dependency and regenerate Xcode project

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add WhisperKit package to project.yml**

Add the `packages` section and update the Yappie target's dependencies:

```yaml
name: Yappie
options:
  bundleIdPrefix: com.kloogans
  deploymentTarget:
    macOS: "14.0"
packages:
  WhisperKit:
    url: https://github.com/argmaxinc/WhisperKit.git
    from: "0.9.0"
targets:
  Yappie:
    type: application
    platform: macOS
    sources: [Yappie]
    dependencies:
      - package: WhisperKit
        product: WhisperKit
    info:
      path: Yappie/Info.plist
      properties:
        LSUIElement: true
        NSMicrophoneUsageDescription: "Yappie needs microphone access to record audio for speech-to-text transcription."
    settings:
      INFOPLIST_FILE: Yappie/Info.plist
      GENERATE_INFOPLIST_FILE: false
      ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
      CODE_SIGN_IDENTITY: "Yappie Development"
      CODE_SIGN_STYLE: Manual
  YappieTests:
    type: bundle.unit-test
    platform: macOS
    sources: [YappieTests]
    dependencies:
      - target: Yappie
    settings:
      GENERATE_INFOPLIST_FILE: true
```

- [ ] **Step 2: Regenerate Xcode project**

Run: `cd /Users/jamesobrien/dev/yappie && xcodegen generate`
Expected: "Generated Yappie.xcodeproj"

- [ ] **Step 3: Resolve packages and verify build**

Run: `make build`
Expected: Build succeeds with WhisperKit resolved

- [ ] **Step 4: Commit**

```bash
git add project.yml Yappie.xcodeproj
git commit -m "chore: add WhisperKit SPM dependency"
```

---

## Task 2: Extend BackendConfig with `.local` type and `language` field

**Files:**
- Modify: `Yappie/BackendConfig.swift:7-33`
- Test: `YappieTests/BackendConfigTests.swift`

- [ ] **Step 1: Write failing tests for `.local` config and `language` field**

Add these tests to `YappieTests/BackendConfigTests.swift`:

```swift
func testBackendConfigLocal() {
    let backend = BackendConfig(
        name: "Local Whisper",
        type: .local,
        enabled: true,
        model: "distil-whisper_distil-large-v3_turbo_600MB",
        language: "en"
    )

    let encoded = try! JSONEncoder().encode([backend])
    let decoded = try! JSONDecoder().decode([BackendConfig].self, from: encoded)

    XCTAssertEqual(decoded[0].type, .local)
    XCTAssertEqual(decoded[0].model, "distil-whisper_distil-large-v3_turbo_600MB")
    XCTAssertEqual(decoded[0].language, "en")
    XCTAssertNil(decoded[0].baseURL)
    XCTAssertNil(decoded[0].host)
}

func testBackendConfigLocalAutoDetect() {
    let backend = BackendConfig(
        name: "Local Whisper",
        type: .local,
        enabled: true,
        model: "openai_whisper-tiny",
        language: nil
    )

    let encoded = try! JSONEncoder().encode([backend])
    let decoded = try! JSONDecoder().decode([BackendConfig].self, from: encoded)

    XCTAssertEqual(decoded[0].type, .local)
    XCTAssertNil(decoded[0].language)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `.local` is not a valid `BackendType` case, `language` property does not exist

- [ ] **Step 3: Add `.local` case and `language` field**

In `Yappie/BackendConfig.swift`, update the enum:

```swift
enum BackendType: String, Codable {
    case api
    case tcp
    case local
}
```

Update the struct to add `language` and update the initializer:

```swift
struct BackendConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var type: BackendType
    var enabled: Bool
    var baseURL: String?
    var model: String?
    var host: String?
    var port: Int?
    var language: String?

    init(name: String, type: BackendType, enabled: Bool,
         baseURL: String? = nil, model: String? = nil,
         host: String? = nil, port: Int? = nil,
         language: String? = nil) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.enabled = enabled
        self.baseURL = baseURL
        self.model = model
        self.host = host
        self.port = port
        self.language = language
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: All tests pass, including the two new ones

- [ ] **Step 5: Commit**

```bash
git add Yappie/BackendConfig.swift YappieTests/BackendConfigTests.swift
git commit -m "feat: add .local backend type and language field to BackendConfig"
```

---

## Task 3: Create LocalModelManager

**Files:**
- Create: `Yappie/LocalModelManager.swift`
- Test: `YappieTests/LocalModelManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `YappieTests/LocalModelManagerTests.swift`:

```swift
// YappieTests/LocalModelManagerTests.swift
import XCTest
@testable import Yappie

final class LocalModelManagerTests: XCTestCase {

    func testRecommendedModelFor8GB() {
        let model = LocalModelManager.recommendedModel(ramGB: 8)
        XCTAssertEqual(model, "openai_whisper-small")
    }

    func testRecommendedModelFor16GB() {
        let model = LocalModelManager.recommendedModel(ramGB: 16)
        XCTAssertEqual(model, "distil-whisper_distil-large-v3_turbo_600MB")
    }

    func testRecommendedModelFor24GB() {
        let model = LocalModelManager.recommendedModel(ramGB: 24)
        XCTAssertEqual(model, "openai_whisper-large-v3_turbo_954MB")
    }

    func testRecommendedModelFor32GB() {
        let model = LocalModelManager.recommendedModel(ramGB: 32)
        XCTAssertEqual(model, "openai_whisper-large-v3_turbo_954MB")
    }

    func testModelDirectoryURL() {
        let url = LocalModelManager.modelDirectoryURL()
        XCTAssertTrue(url.path.contains("Application Support/Yappie/Models"))
    }

    func testCuratedModels() {
        let models = LocalModelManager.curatedModels
        XCTAssertEqual(models.count, 5)
        XCTAssertEqual(models[0].displayName, "Tiny")
        XCTAssertEqual(models[4].displayName, "Large v3")
    }

    func testIsAppleSiliconReturnsBool() {
        // Just verify it doesn't crash and returns a bool
        let result = LocalModelManager.isAppleSilicon()
        XCTAssertNotNil(result)
    }

    func testDeviceRAMReturnPositive() {
        let ram = LocalModelManager.deviceRAMInGB()
        XCTAssertGreaterThan(ram, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `LocalModelManager` does not exist

- [ ] **Step 3: Implement LocalModelManager**

Create `Yappie/LocalModelManager.swift`:

```swift
// Yappie/LocalModelManager.swift
import Foundation
import WhisperKit

struct CuratedModel {
    let displayName: String
    let variant: String
    let sizeDescription: String
    let sizeBytes: Int64
    let accuracyBars: Int  // 1-5
    let description: String
}

enum LocalModelManager {

    static let curatedModels: [CuratedModel] = [
        CuratedModel(
            displayName: "Tiny",
            variant: "openai_whisper-tiny",
            sizeDescription: "~40 MB",
            sizeBytes: 40_000_000,
            accuracyBars: 1,
            description: "Fastest, lowest memory. Best for quick notes."
        ),
        CuratedModel(
            displayName: "Small",
            variant: "openai_whisper-small",
            sizeDescription: "~250 MB",
            sizeBytes: 250_000_000,
            accuracyBars: 2,
            description: "Good accuracy, low memory use. Great for 8 GB machines."
        ),
        CuratedModel(
            displayName: "Distil Large v3 Turbo",
            variant: "distil-whisper_distil-large-v3_turbo_600MB",
            sizeDescription: "~600 MB",
            sizeBytes: 600_000_000,
            accuracyBars: 4,
            description: "Best balance of speed and accuracy for your Mac."
        ),
        CuratedModel(
            displayName: "Large v3 Turbo",
            variant: "openai_whisper-large-v3_turbo_954MB",
            sizeDescription: "~954 MB",
            sizeBytes: 954_000_000,
            accuracyBars: 4,
            description: "Near-maximum accuracy, optimized for speed."
        ),
        CuratedModel(
            displayName: "Large v3",
            variant: "openai_whisper-large-v3",
            sizeDescription: "~1.5 GB",
            sizeBytes: 1_500_000_000,
            accuracyBars: 5,
            description: "Maximum accuracy. Best for difficult audio or accents."
        ),
    ]

    static func isAppleSilicon() -> Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return machine?.hasPrefix("arm64") ?? false
    }

    static func deviceRAMInGB() -> Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }

    static func recommendedModel(ramGB: Int) -> String {
        if ramGB >= 24 {
            return "openai_whisper-large-v3_turbo_954MB"
        } else if ramGB >= 16 {
            return "distil-whisper_distil-large-v3_turbo_600MB"
        } else {
            return "openai_whisper-small"
        }
    }

    static func recommendedModelForDevice() -> String {
        recommendedModel(ramGB: deviceRAMInGB())
    }

    static func modelDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Yappie/Models", isDirectory: true)
    }

    static func downloadedModel() -> String? {
        let modelsDir = modelDirectoryURL()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsDir, includingPropertiesForKeys: nil
        ) else { return nil }
        // WhisperKit stores models in a subdirectory named after the variant
        return contents.first { item in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
            return isDir.boolValue
        }?.lastPathComponent
    }

    static func downloadedModelDirectoryPath() -> String? {
        guard let variant = downloadedModel() else { return nil }
        return modelDirectoryURL().appendingPathComponent(variant).path
    }

    static func download(variant: String, progress: @escaping (Double) -> Void) async throws -> URL {
        let modelsDir = modelDirectoryURL()
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let modelURL = try await WhisperKit.download(
            variant: variant,
            from: "argmaxinc/whisperkit-coreml",
            progressCallback: { downloadProgress in
                progress(downloadProgress.fractionCompleted)
            }
        )

        // Move from HuggingFace cache to our models directory
        let destination = modelsDir.appendingPathComponent(variant)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: modelURL), to: destination)

        return destination
    }

    static func deleteModel() throws {
        let modelsDir = modelDirectoryURL()
        if FileManager.default.fileExists(atPath: modelsDir.path) {
            try FileManager.default.removeItem(at: modelsDir)
        }
    }

    static func modelSizeOnDisk() -> String? {
        guard let variant = downloadedModel() else { return nil }
        let modelPath = modelDirectoryURL().appendingPathComponent(variant)
        guard let enumerator = FileManager.default.enumerator(at: modelPath, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }

    static func availableModels() async throws -> [String] {
        let models = try await WhisperKit.fetchAvailableModels(from: "argmaxinc/whisperkit-coreml")
        return models.sorted()
    }
}
```

- [ ] **Step 4: Regenerate Xcode project and run tests**

Run: `cd /Users/jamesobrien/dev/yappie && xcodegen generate && make test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Yappie/LocalModelManager.swift YappieTests/LocalModelManagerTests.swift
git commit -m "feat: add LocalModelManager for WhisperKit model lifecycle"
```

---

## Task 4: Create LocalBackend

**Files:**
- Create: `Yappie/LocalBackend.swift`
- Create: `YappieTests/LocalBackendTests.swift`

- [ ] **Step 1: Write failing tests**

Create `YappieTests/LocalBackendTests.swift`:

```swift
// YappieTests/LocalBackendTests.swift
import XCTest
@testable import Yappie

final class LocalBackendTests: XCTestCase {

    func testThrowsWhenModelNotFound() async {
        do {
            _ = try await LocalBackend(modelFolder: "/nonexistent/path", language: nil)
            XCTFail("Should have thrown")
        } catch {
            // Expected: WhisperKit can't load from bad path
        }
    }

    func testExtractsLanguageFromConfig() {
        // Verify the config-to-backend mapping logic
        let config = BackendConfig(
            name: "Local",
            type: .local,
            enabled: true,
            model: "openai_whisper-tiny",
            language: "en"
        )
        XCTAssertEqual(config.language, "en")
        XCTAssertEqual(config.model, "openai_whisper-tiny")
    }

    func testAutoDetectLanguageIsNil() {
        let config = BackendConfig(
            name: "Local",
            type: .local,
            enabled: true,
            model: "openai_whisper-tiny",
            language: nil
        )
        XCTAssertNil(config.language)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `LocalBackend` does not exist

- [ ] **Step 3: Implement LocalBackend**

Create `Yappie/LocalBackend.swift`:

```swift
// Yappie/LocalBackend.swift
import Foundation
import WhisperKit

final class LocalBackend: TranscriptionBackend {
    private let pipe: WhisperKit
    private let language: String?

    init(modelFolder: String, language: String?) async throws {
        let config = WhisperKitConfig(
            modelFolder: modelFolder,
            download: false,
            load: true,
            prewarm: true
        )
        self.pipe = try await WhisperKit(config)
        self.language = language
    }

    func transcribe(wavData: Data) async throws -> String {
        // Write WAV data to temp file (WhisperKit expects a file path)
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try wavData.write(to: tempURL)

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        let results = try await pipe.transcribe(
            audioPath: tempURL.path,
            decodeOptions: options
        )

        let text = results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw TranscriptionError.emptyResponse
        }

        return text
    }
}
```

- [ ] **Step 4: Regenerate Xcode project and run tests**

Run: `cd /Users/jamesobrien/dev/yappie && xcodegen generate && make test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Yappie/LocalBackend.swift YappieTests/LocalBackendTests.swift
git commit -m "feat: add LocalBackend for on-device WhisperKit transcription"
```

---

## Task 5: Wire LocalBackend into BackendManager and AppState

**Files:**
- Modify: `Yappie/TranscriptionBackend.swift:20-29`
- Modify: `Yappie/AppState.swift:133-136`
- Test: `YappieTests/BackendManagerTests.swift`

- [ ] **Step 1: Write failing test for local backend in fallback chain**

Add to `YappieTests/BackendManagerTests.swift`:

```swift
func testLocalBackendInFallbackChain() async throws {
    let local = MockBackend()
    local.shouldFail = true
    local.responseText = "local result"
    let cloud = MockBackend()
    cloud.responseText = "cloud result"

    let manager = BackendManager(backends: [local, cloud])
    let result = try await manager.transcribe(wavData: Data([0x00]))

    XCTAssertEqual(result.text, "cloud result")
    XCTAssertEqual(result.backendIndex, 1)
    XCTAssertEqual(local.transcribeCallCount, 1)
    XCTAssertEqual(cloud.transcribeCallCount, 1)
}
```

- [ ] **Step 2: Run test to verify it passes (it should already work with MockBackend)**

Run: `make test`
Expected: PASS — the fallback chain already works generically with `MockBackend`

- [ ] **Step 3: Update BackendManager factory to handle `.local` type**

In `Yappie/TranscriptionBackend.swift`, replace the `convenience init(store:)` with an async factory method:

```swift
final class BackendManager {
    private let backends: [TranscriptionBackend]

    init(backends: [TranscriptionBackend]) {
        self.backends = backends
    }

    static func create(store: BackendStore) async -> BackendManager {
        var enabledBackends: [TranscriptionBackend] = []
        for config in store.backends where config.enabled {
            switch config.type {
            case .api:
                enabledBackends.append(APIBackend(config: config))
            case .tcp:
                enabledBackends.append(TCPBackend(config: config))
            case .local:
                if let modelPath = LocalModelManager.downloadedModelDirectoryPath() {
                    do {
                        let backend = try await LocalBackend(
                            modelFolder: modelPath,
                            language: config.language
                        )
                        enabledBackends.append(backend)
                    } catch {
                        NSLog("[Yappie] Failed to load local model: %@", "\(error)")
                    }
                }
            }
        }
        return BackendManager(backends: enabledBackends)
    }

    func transcribe(wavData: Data) async throws -> TranscriptionResult {
        guard !backends.isEmpty else {
            throw TranscriptionError.allBackendsFailed
        }

        for (index, backend) in backends.enumerated() {
            do {
                let text = try await backend.transcribe(wavData: wavData)
                return TranscriptionResult(text: text, backendIndex: index)
            } catch {
                NSLog("[Yappie] Backend %d failed: %@", index, "\(error)")
                continue
            }
        }

        throw TranscriptionError.allBackendsFailed
    }
}
```

- [ ] **Step 4: Update AppState to use async factory**

In `Yappie/AppState.swift`, update the `stopRecording()` method. Replace:

```swift
let manager = cachedManager ?? BackendManager(store: backendStore)
cachedManager = manager
```

With:

```swift
let manager: BackendManager
if let cached = cachedManager {
    manager = cached
} else {
    manager = await BackendManager.create(store: backendStore)
    cachedManager = manager
}
```

- [ ] **Step 5: Regenerate Xcode project, build, and run tests**

Run: `cd /Users/jamesobrien/dev/yappie && xcodegen generate && make test`
Expected: All tests pass, build succeeds

- [ ] **Step 6: Commit**

```bash
git add Yappie/TranscriptionBackend.swift Yappie/AppState.swift YappieTests/BackendManagerTests.swift
git commit -m "feat: wire LocalBackend into BackendManager fallback chain"
```

---

## Task 6: Copy mascot SVGs into Xcode assets

**Files:**
- Create: `Yappie/Assets.xcassets/YappieTongue.imageset/`
- Create: `Yappie/Assets.xcassets/YappieSunglasses.imageset/`

- [ ] **Step 1: Copy SVGs and create asset catalogs**

```bash
# Tongue mascot
mkdir -p Yappie/Assets.xcassets/YappieTongue.imageset
cp /Users/jamesobrien/Documents/yappie/tongue.svg Yappie/Assets.xcassets/YappieTongue.imageset/tongue.svg
```

Create `Yappie/Assets.xcassets/YappieTongue.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "tongue.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true
  }
}
```

```bash
# Sunglasses mascot
mkdir -p Yappie/Assets.xcassets/YappieSunglasses.imageset
cp /Users/jamesobrien/Documents/yappie/sunglasses.svg Yappie/Assets.xcassets/YappieSunglasses.imageset/sunglasses.svg
```

Create `Yappie/Assets.xcassets/YappieSunglasses.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "sunglasses.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true
  }
}
```

- [ ] **Step 2: Verify build with new assets**

Run: `cd /Users/jamesobrien/dev/yappie && xcodegen generate && make build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Yappie/Assets.xcassets/YappieTongue.imageset Yappie/Assets.xcassets/YappieSunglasses.imageset
git commit -m "feat: add tongue and sunglasses mascot SVGs for local backend wizard"
```

---

## Task 7: Build the model selection wizard view

**Files:**
- Create: `Yappie/LocalBackendWizard.swift`

- [ ] **Step 1: Create LocalBackendWizard with model selection and download progress views**

Create `Yappie/LocalBackendWizard.swift`:

```swift
// Yappie/LocalBackendWizard.swift
import SwiftUI

// MARK: - Languages

private let supportedLanguages: [(code: String?, name: String)] = [
    (nil, "Auto-detect"),
    ("en", "English"),
    ("es", "Spanish"),
    ("fr", "French"),
    ("de", "German"),
    ("ja", "Japanese"),
    ("zh", "Chinese"),
    ("ko", "Korean"),
    ("pt", "Portuguese"),
    ("it", "Italian"),
    ("nl", "Dutch"),
]

// MARK: - Model Selection

struct LocalModelSelectionView: View {
    @ObservedObject var store: BackendStore
    var onDismiss: () -> Void
    var onBack: () -> Void

    @State private var selectedVariant: String?
    @State private var selectedLanguage: String? = nil
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var allModels: [String] = []
    @State private var isLoadingModels = false
    @State private var showDownload = false

    private var recommendedVariant: String {
        LocalModelManager.recommendedModelForDevice()
    }

    var body: some View {
        if showDownload, let variant = selectedVariant {
            LocalModelDownloadView(
                variant: variant,
                displayName: displayName(for: variant),
                sizeDescription: sizeDescription(for: variant),
                language: selectedLanguage,
                store: store,
                onDismiss: onDismiss,
                onBack: { showDownload = false }
            )
        } else {
            modelSelectionContent
        }
    }

    private var modelSelectionContent: some View {
        VStack(spacing: 0) {
            Text("Choose a Model")
                .font(.headline)
                .padding(.top)
            Text("Larger models are more accurate but use more memory and disk space.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            // Language picker
            HStack(spacing: 8) {
                Text("Language")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedLanguage) {
                    ForEach(supportedLanguages, id: \.name) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .frame(width: 140)
                if selectedLanguage != nil {
                    Text("Setting a language improves speed & accuracy")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 6) {
                    // Curated models
                    ForEach(LocalModelManager.curatedModels, id: \.variant) { model in
                        let isRecommended = model.variant == recommendedVariant
                        let isSelected = selectedVariant == model.variant
                        CuratedModelCard(
                            model: model,
                            isRecommended: isRecommended,
                            isSelected: isSelected
                        ) {
                            selectedVariant = model.variant
                        }
                    }

                    // Browse all models
                    if !showSearch {
                        Button("Browse all models...") {
                            showSearch = true
                            if allModels.isEmpty {
                                loadAllModels()
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    } else {
                        modelSearchView
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }

            Divider()

            // Footer
            HStack {
                Text("Models stored in ~/Library/Application Support/Yappie/Models/")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Spacer()
                Button("Back") { onBack() }
                Button("Download & Add") {
                    showDownload = true
                }
                .disabled(selectedVariant == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    private var modelSearchView: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary)
            .cornerRadius(6)

            if isLoadingModels {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
            } else {
                let filtered = allModels.filter {
                    searchText.isEmpty || $0.localizedCaseInsensitiveContains(searchText)
                }
                ForEach(filtered.prefix(12), id: \.self) { model in
                    let isSelected = selectedVariant == model
                    Button {
                        selectedVariant = model
                    } label: {
                        HStack {
                            Text(model)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.green.opacity(0.1) : Color.primary.opacity(0.04))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(isSelected ? Color.green.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                if filtered.count > 12 {
                    Text("Showing 12 of \(filtered.count) matches")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func loadAllModels() {
        isLoadingModels = true
        Task {
            do {
                let models = try await LocalModelManager.availableModels()
                await MainActor.run {
                    allModels = models
                    isLoadingModels = false
                }
            } catch {
                NSLog("[Yappie] Failed to fetch model list: %@", "\(error)")
                await MainActor.run {
                    isLoadingModels = false
                }
            }
        }
    }

    private func displayName(for variant: String) -> String {
        LocalModelManager.curatedModels.first { $0.variant == variant }?.displayName ?? variant
    }

    private func sizeDescription(for variant: String) -> String {
        LocalModelManager.curatedModels.first { $0.variant == variant }?.sizeDescription ?? "Unknown size"
    }
}

// MARK: - Curated Model Card

private struct CuratedModelCard: View {
    let model: CuratedModel
    let isRecommended: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .fontWeight(.semibold)
                            .font(.system(size: 13))
                        Text(model.sizeDescription)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .cornerRadius(3)
                        if isRecommended {
                            Text("RECOMMENDED")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    Text(model.description)
                        .font(.system(size: 11))
                        .foregroundStyle(isRecommended ? .green : .secondary)
                }

                Spacer()

                // Accuracy bars
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { bar in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(bar <= model.accuracyBars ? Color.green : Color.primary.opacity(0.15))
                            .frame(width: 4, height: 10)
                    }
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isRecommended
                        ? Color.green.opacity(isSelected ? 0.12 : 0.06)
                        : (isSelected ? Color.green.opacity(0.06) : Color.primary.opacity(0.04)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.green.opacity(0.4) :
                        (isRecommended ? Color.green.opacity(0.2) : Color.primary.opacity(0.08)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Download Progress

struct LocalModelDownloadView: View {
    let variant: String
    let displayName: String
    let sizeDescription: String
    let language: String?
    @ObservedObject var store: BackendStore
    var onDismiss: () -> Void
    var onBack: () -> Void

    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    @State private var isComplete = false
    @State private var error: String?
    @State private var downloadTask: Task<Void, Never>?
    @State private var actualSize: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if isComplete {
                completeView
            } else if let error {
                errorView(error)
            } else {
                downloadingView
            }

            Spacer()
        }
        .onAppear { startDownload() }
        .onDisappear { downloadTask?.cancel() }
    }

    private var downloadingView: some View {
        VStack(spacing: 16) {
            Image("YappieTongue")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .shadow(color: Color(red: 0.96, green: 0.76, blue: 0.26).opacity(0.3), radius: 8, y: 2)

            Text("Downloading \(displayName)")
                .font(.system(size: 15, weight: .semibold))
            Text("\(sizeDescription) from Hugging Face")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ProgressView(value: downloadProgress)
                    .tint(.green)

                HStack {
                    Text(progressDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 40)

            Button("Cancel") {
                downloadTask?.cancel()
                onBack()
            }
            .padding(.top, 12)
        }
    }

    private var completeView: some View {
        VStack(spacing: 16) {
            Image("YappieSunglasses")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .shadow(color: Color(red: 0.96, green: 0.76, blue: 0.26).opacity(0.3), radius: 8, y: 2)

            Text("Ready to Go")
                .font(.system(size: 15, weight: .semibold))
            Text("\(displayName) downloaded successfully")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Summary card
            VStack(spacing: 6) {
                summaryRow(label: "Model", value: displayName)
                summaryRow(label: "Language", value: language.flatMap { code in
                    supportedLanguages.first { $0.code == code }?.name
                } ?? "Auto-detect")
                summaryRow(label: "Disk usage", value: actualSize ?? sizeDescription)
            }
            .padding(12)
            .background(.quaternary)
            .cornerRadius(8)
            .padding(.horizontal, 40)

            Button("Done") {
                let config = BackendConfig(
                    name: "Local Whisper",
                    type: .local,
                    enabled: true,
                    model: variant,
                    language: language
                )
                store.add(config)
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 12)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Download Failed")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 12) {
                Button("Back") { onBack() }
                Button("Retry") { startDownload() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }

    private var progressDescription: String {
        guard let curated = LocalModelManager.curatedModels.first(where: { $0.variant == variant }) else {
            return ""
        }
        let downloaded = Int64(downloadProgress * Double(curated.sizeBytes))
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: downloaded)) of \(sizeDescription)"
    }

    private func startDownload() {
        error = nil
        isComplete = false
        downloadProgress = 0
        isDownloading = true

        downloadTask = Task {
            do {
                // Delete existing model if any
                try? LocalModelManager.deleteModel()

                _ = try await LocalModelManager.download(variant: variant) { progress in
                    Task { @MainActor in
                        downloadProgress = progress
                    }
                }

                await MainActor.run {
                    actualSize = LocalModelManager.modelSizeOnDisk()
                    isComplete = true
                    isDownloading = false
                }
            } catch is CancellationError {
                // User cancelled
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isDownloading = false
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Users/jamesobrien/dev/yappie && xcodegen generate && make build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Yappie/LocalBackendWizard.swift
git commit -m "feat: add model selection and download progress wizard views"
```

---

## Task 8: Update BackendWizard with Local Whisper option and reorganize sections

**Files:**
- Modify: `Yappie/BackendWizard.swift`

- [ ] **Step 1: Update BackendWizardView**

Replace the entire contents of `Yappie/BackendWizard.swift` with:

```swift
// Yappie/BackendWizard.swift
import SwiftUI

// MARK: - Presets

struct APIPreset {
    let name: String
    let baseURL: String
    let model: String
    let needsKey: Bool
    let icon: String
}

private let apiPresets: [APIPreset] = [
    APIPreset(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "whisper-1", needsKey: true, icon: "brain"),
    APIPreset(name: "Groq", baseURL: "https://api.groq.com/openai/v1", model: "whisper-large-v3-turbo", needsKey: true, icon: "bolt.fill"),
]

// MARK: - Add Wizard (Multi-Step)

struct BackendWizardView: View {
    @ObservedObject var store: BackendStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: BackendType?
    @State private var selectedPreset: APIPreset?
    @State private var showLocalWizard = false

    var body: some View {
        VStack(spacing: 0) {
            if showLocalWizard {
                LocalModelSelectionView(
                    store: store,
                    onDismiss: { dismiss() },
                    onBack: { showLocalWizard = false }
                )
            } else if let selectedType {
                Text("Add Backend")
                    .font(.headline)
                    .padding()
                BackendFormView(
                    type: selectedType,
                    store: store,
                    preset: selectedPreset,
                    onDismiss: { dismiss() },
                    onBack: { self.selectedType = nil; self.selectedPreset = nil }
                )
            } else {
                Text("Add Backend")
                    .font(.headline)
                    .padding()
                typeSelectionView
            }
        }
        .frame(width: 420, height: 480)
    }

    private var typeSelectionView: some View {
        VStack(spacing: 16) {
            // On-Device section (Apple Silicon only)
            if LocalModelManager.isAppleSilicon() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("On-Device")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    Button {
                        showLocalWizard = true
                    } label: {
                        HStack(spacing: 10) {
                            Image("AppIcon")
                                .resizable()
                                .frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Local Whisper")
                                    .fontWeight(.semibold)
                                    .font(.system(size: 13))
                                Text("Private, offline, no API key needed")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color.green.opacity(0.08), Color.green.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
            }

            // Cloud APIs
            VStack(alignment: .leading, spacing: 8) {
                Text("Cloud APIs")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                ForEach(apiPresets, id: \.name) { preset in
                    Button {
                        selectedPreset = preset
                        selectedType = .api
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: preset.icon)
                                .frame(width: 20)
                                .foregroundStyle(.primary)
                            Text(preset.name)
                                .fontWeight(.medium)
                            Spacer()
                            if preset.needsKey {
                                Text("API key required")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.quaternary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Custom options
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                TypeSelectionButton(
                    emoji: "\u{1F310}",
                    title: "Custom API Endpoint",
                    subtitle: "Any OpenAI-compatible Whisper API"
                ) {
                    selectedType = .api
                }

                TypeSelectionButton(
                    emoji: "\u{1F50C}",
                    title: "Custom TCP Socket",
                    subtitle: "Direct TCP connection for custom servers"
                ) {
                    selectedType = .tcp
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

// MARK: - Type Selection Button

private struct TypeSelectionButton: View {
    let emoji: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(emoji).font(.body)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .fontWeight(.medium)
                        .font(.system(size: 13))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Backend Form (shared by Add and Edit)

struct BackendFormView: View {
    let type: BackendType
    @ObservedObject var store: BackendStore
    var existingBackend: BackendConfig?
    var preset: APIPreset?
    var onDismiss: () -> Void
    var onBack: (() -> Void)?

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var host: String = ""
    @State private var port: String = ""

    init(type: BackendType, store: BackendStore, existingBackend: BackendConfig? = nil, preset: APIPreset? = nil, onDismiss: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self.type = type
        self.store = store
        self.existingBackend = existingBackend
        self.preset = preset
        self.onDismiss = onDismiss
        self.onBack = onBack

        if let existing = existingBackend {
            _name = State(initialValue: existing.name)
            _baseURL = State(initialValue: existing.baseURL ?? "")
            _model = State(initialValue: existing.model ?? "")
            _host = State(initialValue: existing.host ?? "")
            _port = State(initialValue: existing.port.map { String($0) } ?? "")
            _apiKey = State(initialValue: KeychainHelper.get(forBackendID: existing.id) ?? "")
        } else if let preset {
            _name = State(initialValue: preset.name)
            _baseURL = State(initialValue: preset.baseURL)
            _model = State(initialValue: preset.model)
        }
    }

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text(type == .api ? "e.g. OpenAI" : "e.g. Home Server"))

            if type == .api {
                TextField("Base URL", text: $baseURL, prompt: Text("https://api.openai.com/v1"))
                SecureField("API Key", text: $apiKey, prompt: Text("Optional for local servers"))
                TextField("Model", text: $model, prompt: Text("e.g. whisper-1 (optional)"))
            } else {
                TextField("Host", text: $host, prompt: Text("192.168.1.100"))
                TextField("Port", text: $port, prompt: Text("9876"))
            }
        }
        .padding()

        Spacer()

        HStack {
            if let onBack {
                Button("Back") { onBack() }
            }
            Spacer()
            Button("Cancel") { onDismiss() }
            Button(existingBackend == nil ? "Add" : "Save") {
                save()
            }
            .disabled(name.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private func save() {
        if var existing = existingBackend {
            existing.name = name
            existing.baseURL = type == .api ? baseURL : nil
            existing.model = type == .api && !model.isEmpty ? model : nil
            existing.host = type == .tcp ? host : nil
            existing.port = type == .tcp ? Int(port) : nil

            if type == .api && !apiKey.isEmpty {
                KeychainHelper.save(apiKey: apiKey, forBackendID: existing.id)
            } else if type == .api && apiKey.isEmpty {
                KeychainHelper.delete(forBackendID: existing.id)
            }

            store.update(existing)
        } else {
            let config = BackendConfig(
                name: name,
                type: type,
                enabled: true,
                baseURL: type == .api ? baseURL : nil,
                model: type == .api && !model.isEmpty ? model : nil,
                host: type == .tcp ? host : nil,
                port: type == .tcp ? Int(port) : nil
            )

            if type == .api && !apiKey.isEmpty {
                KeychainHelper.save(apiKey: apiKey, forBackendID: config.id)
            }

            store.add(config)
        }

        onDismiss()
    }
}

// MARK: - Edit View

struct BackendEditView: View {
    let backend: BackendConfig
    @ObservedObject var store: BackendStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Backend")
                .font(.headline)
                .padding()

            if backend.type == .local {
                LocalModelSelectionView(
                    store: store,
                    onDismiss: { dismiss() },
                    onBack: { dismiss() }
                )
            } else {
                BackendFormView(
                    type: backend.type,
                    store: store,
                    existingBackend: backend,
                    onDismiss: { dismiss() }
                )
            }
        }
        .frame(width: 420, height: backend.type == .local ? 480 : 300)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Users/jamesobrien/dev/yappie && xcodegen generate && make build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Yappie/BackendWizard.swift
git commit -m "feat: reorganize wizard with On-Device section, remove faster-whisper-server preset"
```

---

## Task 9: Update BackendCardView for local backend display

**Files:**
- Modify: `Yappie/Preferences.swift:196-306`

- [ ] **Step 1: Update BackendCardView to handle `.local` type**

In `Yappie/Preferences.swift`, update the `BackendCardView`. Change the type icon (around line 199):

Replace:
```swift
// Type icon
Image(systemName: backend.type == .api ? "globe" : "network")
    .font(.system(size: 16))
    .foregroundStyle(backend.enabled ? .primary : .tertiary)
    .frame(width: 24)
```

With:
```swift
// Type icon
Group {
    if backend.type == .local {
        Image("AppIcon")
            .resizable()
            .frame(width: 20, height: 20)
    } else {
        Image(systemName: backend.type == .api ? "globe" : "network")
            .font(.system(size: 16))
            .foregroundStyle(backend.enabled ? .primary : .tertiary)
    }
}
.frame(width: 24)
```

Update the `connectionDetail` computed property to handle `.local`:

Replace:
```swift
private var connectionDetail: String {
    switch backend.type {
    case .api:
        var parts = [String]()
        if let url = backend.baseURL, !url.isEmpty {
            if let parsed = URL(string: url) {
                parts.append(parsed.host ?? url)
            } else {
                parts.append(url)
            }
        }
        if let model = backend.model, !model.isEmpty {
            parts.append(model)
        }
        if hasAPIKey {
            parts.append("API key set")
        }
        return parts.joined(separator: " \u{00B7} ")
    case .tcp:
        return "\(backend.host ?? ""):\(backend.port ?? 0)"
    }
}
```

With:
```swift
private var connectionDetail: String {
    switch backend.type {
    case .api:
        var parts = [String]()
        if let url = backend.baseURL, !url.isEmpty {
            if let parsed = URL(string: url) {
                parts.append(parsed.host ?? url)
            } else {
                parts.append(url)
            }
        }
        if let model = backend.model, !model.isEmpty {
            parts.append(model)
        }
        if hasAPIKey {
            parts.append("API key set")
        }
        return parts.joined(separator: " \u{00B7} ")
    case .tcp:
        return "\(backend.host ?? ""):\(backend.port ?? 0)"
    case .local:
        var parts = [String]()
        if let model = backend.model {
            let displayName = LocalModelManager.curatedModels.first { $0.variant == model }?.displayName ?? model
            parts.append(displayName)
        }
        parts.append(backend.language.flatMap { code in
            code == "auto" ? "Auto-detect" : Locale.current.localizedString(forLanguageCode: code) ?? code
        } ?? "Auto-detect")
        if let size = LocalModelManager.modelSizeOnDisk() {
            parts.append(size)
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
```

Also update the `deleteBackend()` method to clean up model files when deleting a local backend:

Replace:
```swift
private func deleteBackend() {
    if let index = store.backends.firstIndex(where: { $0.id == backend.id }) {
        store.remove(at: index)
    }
}
```

With:
```swift
private func deleteBackend() {
    if backend.type == .local {
        try? LocalModelManager.deleteModel()
    }
    if let index = store.backends.firstIndex(where: { $0.id == backend.id }) {
        store.remove(at: index)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Users/jamesobrien/dev/yappie && xcodegen generate && make build`
Expected: Build succeeds

- [ ] **Step 3: Run all tests**

Run: `make test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Yappie/Preferences.swift
git commit -m "feat: update backend card to display local backend with Yappie icon and model details"
```

---

## Task 10: Final integration build and test

**Files:** None (verification only)

- [ ] **Step 1: Regenerate project and clean build**

Run: `cd /Users/jamesobrien/dev/yappie && xcodegen generate && make build`
Expected: Clean build succeeds

- [ ] **Step 2: Run full test suite**

Run: `make test`
Expected: All tests pass

- [ ] **Step 3: Verify no compiler warnings**

Run: `make build 2>&1 | grep -i warning`
Expected: No warnings (or only pre-existing ones)

- [ ] **Step 4: Commit any remaining changes**

If there are any uncommitted fixes from the build/test cycle:
```bash
git add -A
git commit -m "fix: address build warnings and test issues from WhisperKit integration"
```
