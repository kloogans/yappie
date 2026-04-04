// Yappie/AppState.swift
import SwiftUI
import AVFoundation

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
    @AppStorage("recordingMode") var recordingMode = RecordingMode.pushToTalk.rawValue
    @AppStorage("deliveryMode") var deliveryMode = DeliveryMode.clipboardAndPaste.rawValue

    private let recorder = AudioRecorder()
    private let client = TranscriptionClient()
    let hotkeyManager = HotkeyManager()
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
    }

    func applyRecordingMode() {
        hotkeyManager.stopFnMonitor()
        hotkeyManager.unregisterToggleHotkey()

        if recordingMode == RecordingMode.pushToTalk.rawValue {
            hotkeyManager.startFnMonitor()
        }
    }

    func startRecording() {
        guard status == .idle else { return }
        do {
            try recorder.startRecording()
            status = .recording
            recordingDuration = 0
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordingDuration += 0.1
                }
            }
        } catch {
            NSLog("[Yappie] Recording failed: %@", "\(error)")
        }
    }

    func stopRecording() {
        guard status == .recording else { return }
        durationTimer?.invalidate()
        durationTimer = nil

        let wavData = recorder.stopRecording()
        status = .transcribing

        Task {
            do {
                let text = try await client.transcribe(
                    wavData: wavData,
                    host: serverHost,
                    port: UInt16(serverPort)
                )
                let mode = DeliveryMode(rawValue: deliveryMode) ?? .clipboardAndPaste
                TextDelivery.deliver(text, mode: mode)
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
