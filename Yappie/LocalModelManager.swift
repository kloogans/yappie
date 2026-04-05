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
        try FileManager.default.copyItem(at: modelURL, to: destination)

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
