// Yappie/AppState.swift
import SwiftUI
import UserNotifications
import Combine

enum RecordingMode: String {
    case pushToTalk = "push-to-talk"
    case toggle = "toggle"
}

enum AppStatus {
    case idle
    case recording
    case transcribing
}

enum ModelLoadingStatus {
    case idle
    case loading
    case ready
    case failed
}

@MainActor
final class AppState: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var recordingDuration: TimeInterval = 0
    @Published var modelLoadingStatus: ModelLoadingStatus = .idle

    @AppStorage("recordingMode") var recordingMode: RecordingMode = .pushToTalk
    @AppStorage("deliveryMode") var deliveryMode: DeliveryMode = .clipboardAndPaste
    @AppStorage("hotkeyCode") var hotkeyCode: Int = -1
    @AppStorage("hotkeyModifiers") var hotkeyModifiers: Int = 0

    private let recorder = AudioRecorder()
    let backendStore = BackendStore()
    private let hotkeyManager = HotkeyManager()
    private var hasShownFallbackNotice = false
    private var durationTimer: Timer?
    private var lastAppliedMode: RecordingMode?
    private var lastAppliedHotkeyCode: Int?
    private var lastAppliedHotkeyModifiers: Int?
    private var cachedManager: BackendManager?
    private var cancellables = Set<AnyCancellable>()
    private weak var statusItemButton: NSStatusBarButton?

    var statusIcon: String {
        switch status {
        case .idle: "mic"
        case .recording: "mic.fill"
        case .transcribing: "ellipsis.circle"
        }
    }

    init() {
        DispatchQueue.main.async { [weak self] in
            self?.setup()
        }
    }

    func setup() {
        if backendStore.backends.isEmpty {
            backendStore.migrateFromLegacySettings()
        }

        hotkeyManager.onRecordStart = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotkeyManager.onRecordStop = { [weak self] in
            Task { @MainActor in self?.stopRecording() }
        }
        applyRecordingMode()

        // Re-apply recording mode when preference changes
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyRecordingMode()
        }

        // Invalidate cached BackendManager when backends change
        backendStore.$backends
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.cachedManager = nil
            }
            .store(in: &cancellables)

        configureStatusItem()

        $modelLoadingStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarText() }
            .store(in: &cancellables)

        $status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarText() }
            .store(in: &cancellables)

        // Preload backends (so WhisperKit model is ready before first recording)
        if backendStore.enabledBackends.contains(where: { $0.type == .local }) {
            modelLoadingStatus = .loading
            showNotification(title: "Yappie", body: "Preparing speech model. This may take a moment on first launch.", autoDismiss: 5)
        }
        let store = backendStore
        Task.detached {
            debugLog("[Yappie] Preloading backends...")
            let manager = await BackendManager.create(store: store)
            await MainActor.run {
                self.cachedManager = manager
                if let loadTime = manager.localModelLoadTime {
                    self.modelLoadingStatus = .ready
                    self.showNotification(title: "Yappie", body: "Ready to transcribe", autoDismiss: 3)
                    debugLog("[Yappie] Model ready (\(String(format: "%.1f", loadTime))s)")
                } else if self.modelLoadingStatus == .loading {
                    self.modelLoadingStatus = .failed
                    self.showNotification(title: "Yappie", body: "Failed to load speech model. Check Preferences.")
                }
                debugLog("[Yappie] Backends ready")
            }
        }
    }

    func applyRecordingMode() {
        let modeChanged = recordingMode != lastAppliedMode
        let hotkeyChanged = hotkeyCode != lastAppliedHotkeyCode || hotkeyModifiers != lastAppliedHotkeyModifiers
        guard modeChanged || hotkeyChanged else { return }

        lastAppliedMode = recordingMode
        lastAppliedHotkeyCode = hotkeyCode
        lastAppliedHotkeyModifiers = hotkeyModifiers

        hotkeyManager.stopFnMonitor()
        hotkeyManager.unregisterHotkey()

        if hotkeyCode == -1 {
            // Default: Fn key (push-to-talk only, toggle uses menubar)
            if recordingMode == .pushToTalk {
                hotkeyManager.startFnMonitor()
            }
        } else {
            // Custom hotkey via Carbon
            hotkeyManager.registerHotkey(
                keyCode: UInt32(hotkeyCode),
                modifiers: UInt32(hotkeyModifiers),
                pushToTalk: recordingMode == .pushToTalk
            )
        }
    }

    func startRecording() {
        guard status == .idle else { return }
        if modelLoadingStatus == .loading {
            showNotification(title: "Yappie", body: "Still preparing the speech model. You'll be notified when it's ready.")
            return
        }
        if modelLoadingStatus == .failed {
            showNotification(title: "Yappie", body: "Speech model failed to load. Open Preferences to fix.")
            return
        }
        do {
            try recorder.startRecording()
            AudioFeedback.playStart()
            status = .recording
            recordingDuration = 0
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.recordingDuration += 0.1
            }
        } catch {
            NSLog("[Yappie] Recording failed: %@", "\(error)")
        }
    }

    func stopRecording() {
        guard status == .recording else { return }
        durationTimer?.invalidate()
        durationTimer = nil

        AudioFeedback.playStop()
        let wavData = recorder.stopRecording()
        status = .transcribing

        Task { @MainActor in
            do {
                debugLog("[Yappie] stopRecording: wavData size = \(wavData.count) bytes")
                let manager: BackendManager
                if let cached = cachedManager {
                    debugLog("[Yappie] Using cached BackendManager")
                    manager = cached
                } else {
                    debugLog("[Yappie] Creating new BackendManager...")
                    manager = await BackendManager.create(store: backendStore)
                    cachedManager = manager
                    debugLog("[Yappie] BackendManager created")
                }
                debugLog("[Yappie] Starting transcription...")
                let result = try await manager.transcribe(wavData: wavData)
                debugLog("[Yappie] Transcription result: '\(result.text)' (backend \(result.backendIndex))")

                if result.backendIndex > 0 && !hasShownFallbackNotice {
                    hasShownFallbackNotice = true
                    let enabledBackends = backendStore.enabledBackends
                    if result.backendIndex < enabledBackends.count {
                        let name = enabledBackends[result.backendIndex].name
                        showNotification(title: "Yappie", body: "Using \(name)")
                    }
                }

                TextDelivery.deliver(result.text, mode: deliveryMode)
            } catch {
                debugLog("[Yappie] Transcription FAILED: \(error)")
                NSLog("[Yappie] Transcription failed: %@", "\(error)")
                showNotification(title: "Yappie", body: "Transcription failed. No backends available.")
            }
            status = .idle
        }
    }

    func toggleRecording() {
        if status == .idle {
            startRecording()
        } else if status == .recording {
            stopRecording()
        }
    }

    func configureStatusItem() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            for window in NSApp.windows {
                if let statusItem = window.value(forKey: "statusItem") as? NSStatusItem,
                   let button = statusItem.button,
                   button.image?.name() == "MenuBarIcon" {
                    self?.statusItemButton = button
                    self?.updateMenuBarText()
                    return
                }
            }
        }
    }

    private func updateMenuBarText() {
        guard let button = statusItemButton else { return }
        switch modelLoadingStatus {
        case .loading:
            button.title = " Loading…"
            button.imagePosition = .imageLeading
        case .failed:
            button.title = " ⚠"
            button.imagePosition = .imageLeading
        case .ready, .idle:
            switch status {
            case .recording:
                button.title = " REC"
                button.imagePosition = .imageLeading
            case .transcribing:
                button.title = " …"
                button.imagePosition = .imageLeading
            case .idle:
                button.title = ""
                button.imagePosition = .imageOnly
            }
        }
    }

    func showNotification(title: String, body: String, autoDismiss: TimeInterval? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil

        let id = "yappie-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                debugLog("[Yappie] Notification failed: \(error)")
            }
        }

        if let seconds = autoDismiss {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
            }
        }
    }
}
