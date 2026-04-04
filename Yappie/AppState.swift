// Yappie/AppState.swift
import SwiftUI

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

    private let recorder = AudioRecorder()
    let backendStore = BackendStore()
    private let hotkeyManager = HotkeyManager()
    private var hasShownFallbackNotice = false
    private var durationTimer: Timer?

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
    }

    func applyRecordingMode() {
        hotkeyManager.stopFnMonitor()
        hotkeyManager.unregisterToggleHotkey()

        if recordingMode == .pushToTalk {
            hotkeyManager.startFnMonitor()
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
                let manager = BackendManager(store: backendStore)
                let result = try await manager.transcribe(wavData: wavData)

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
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        NSUserNotificationCenter.default.deliver(notification)
    }
}
