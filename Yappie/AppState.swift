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

    @AppStorage("serverHost") var serverHost = "192.168.4.24"
    @AppStorage("serverPort") var serverPort = 9876
    @AppStorage("recordingMode") var recordingMode: RecordingMode = .pushToTalk
    @AppStorage("deliveryMode") var deliveryMode: DeliveryMode = .clipboardAndPaste

    private let recorder = AudioRecorder()
    // Temporarily use TCPBackend with a default config for compilation
    private let client = TCPBackend(config: BackendConfig(name: "Default", type: .tcp, enabled: true, host: "192.168.4.24", port: 9876))
    private let hotkeyManager = HotkeyManager()
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
                let text = try await client.transcribe(wavData: wavData)
                TextDelivery.deliver(text, mode: deliveryMode)
            } catch {
                NSLog("[Yappie] Transcription failed: %@", "\(error)")
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
}
