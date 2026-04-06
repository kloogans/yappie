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
    @Published var loadingBackendIDs: Set<UUID> = []

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
    private var preloadTask: Task<Void, Never>?
    private var notificationsAuthorized = false

    var statusIcon: String {
        switch status {
        case .idle: "mic"
        case .recording: "mic.fill"
        case .transcribing: "ellipsis.circle"
        }
    }

    init() {
        Task { @MainActor in
            await self.setup()
        }
    }

    func setup() async {
        // Ensure notification permission is granted before sending any notifications
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        notificationsAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        debugLog("[Yappie] Notification permission: \(notificationsAuthorized ? "granted" : "denied")")
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

        // Reload backends when config changes (e.g. after wizard adds a new backend)
        backendStore.$backends
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.cachedManager = nil
                self?.preloadBackends()
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

        preloadBackends()
    }

    private func preloadBackends() {
        preloadTask?.cancel()
        modelLoadingStatus = .idle

        let localIDs = Set(backendStore.enabledBackends.filter { $0.type == .local }.map(\.id))
        if !localIDs.isEmpty {
            loadingBackendIDs = localIDs
            modelLoadingStatus = .loading
            showNotification(body: "Preparing speech model. This may take a moment on first launch.", autoDismiss: 5)
        }
        let store = backendStore
        preloadTask = Task { @MainActor [weak self] in
            debugLog("[Yappie] Preloading backends...")
            let manager = await BackendManager.create(store: store) { [weak self] loadedID in
                self?.loadingBackendIDs.remove(loadedID)
            }
            guard !Task.isCancelled, let self else { return }
            self.cachedManager = manager
            if let loadTime = manager.localModelLoadTime {
                self.modelLoadingStatus = .ready
                self.showNotification(body: "Ready to transcribe", autoDismiss: 3)
                debugLog("[Yappie] Model ready (\(String(format: "%.1f", loadTime))s)")
            } else if self.modelLoadingStatus == .loading {
                self.modelLoadingStatus = .failed
                self.showNotification(body: "Failed to load speech model. Check Preferences.")
            }
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
        if modelLoadingStatus == .loading {
            showNotification(body: "Still preparing the speech model. You'll be notified when it's ready.")
            return
        }
        if modelLoadingStatus == .failed {
            showNotification(body: "Speech model failed to load. Open Preferences to fix.")
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
            debugLog("[Yappie] Recording failed: \(error)")
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
                let enabledBackends = backendStore.enabledBackends
                let usedBackend = result.backendIndex < enabledBackends.count ? enabledBackends[result.backendIndex] : nil
                let usedModel = usedBackend?.model ?? "unknown"
                debugLog("[Yappie] Transcription result: '\(result.text)' (backend \(result.backendIndex): \(usedBackend?.name ?? "?") model=\(usedModel))")

                if result.backendIndex > 0 && !hasShownFallbackNotice {
                    hasShownFallbackNotice = true
                    if let backend = usedBackend {
                        let modelName = backend.model.map { LocalModelManager.displayName(for: $0) } ?? backend.name
                        showNotification(body: "Using fallback: \(modelName)")
                    }
                }

                TextDelivery.deliver(result.text, mode: deliveryMode)
            } catch {
                debugLog("[Yappie] Transcription FAILED: \(error)")
                showNotification(body: "Transcription failed. No backends available.")
            }
            status = .idle
        }
    }

    func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
        loadingBackendIDs.removeAll()
        if modelLoadingStatus == .loading {
            modelLoadingStatus = .idle
        }
        cachedManager = nil
        debugLog("[Yappie] Preload cancelled by user")
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

    func showNotification(title: String = "Yappie", body: String, autoDismiss: TimeInterval? = nil) {
        guard notificationsAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil

        let id = "yappie-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()

        center.add(request) { error in
            if let error {
                debugLog("[Yappie] Notification failed: \(error)")
            }
        }

        if let seconds = autoDismiss {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                center.removeDeliveredNotifications(withIdentifiers: [id])
            }
        }
    }
}

// Allow notifications to display as banners even when the app is active
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
