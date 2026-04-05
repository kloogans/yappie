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

@MainActor
final class AppState: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var recordingDuration: TimeInterval = 0

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

        // Preload backends (so WhisperKit model is ready before first recording)
        Task { @MainActor in
            debugLog("[Yappie] Preloading backends...")
            let manager = await BackendManager.create(store: backendStore)
            cachedManager = manager
            debugLog("[Yappie] Backends ready")
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
                debugLog("[Yappie DEBUG] stopRecording: wavData size = \(wavData.count) bytes")
                let manager: BackendManager
                if let cached = cachedManager {
                    debugLog("[Yappie DEBUG] Using cached BackendManager")
                    manager = cached
                } else {
                    debugLog("[Yappie DEBUG] Creating new BackendManager...")
                    manager = await BackendManager.create(store: backendStore)
                    cachedManager = manager
                    debugLog("[Yappie DEBUG] BackendManager created")
                }
                debugLog("[Yappie DEBUG] Starting transcription...")
                let result = try await manager.transcribe(wavData: wavData)
                debugLog("[Yappie DEBUG] Transcription result: '\(result.text)' (backend \(result.backendIndex))")

                if result.backendIndex > 0 && !hasShownFallbackNotice {
                    hasShownFallbackNotice = true
                    let enabledBackends = backendStore.backends.filter { $0.enabled }
                    if result.backendIndex < enabledBackends.count {
                        let name = enabledBackends[result.backendIndex].name
                        showNotification(title: "Yappie", body: "Using \(name)")
                    }
                }

                TextDelivery.deliver(result.text, mode: deliveryMode)
            } catch {
                debugLog("[Yappie DEBUG] Transcription FAILED: \(error)")
                NSLog("[Yappie] Transcription failed: %@", "\(error)")
                showNotification(title: "Yappie", body: "Transcription failed — no backends available")
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

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
