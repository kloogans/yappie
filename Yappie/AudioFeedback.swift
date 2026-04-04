// Yappie/AudioFeedback.swift
import AppKit

enum AudioFeedback {
    private static let startSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "knock_start", withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }()

    private static let stopSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "knock_stop", withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }()

    static func playStart() {
        startSound?.stop()
        startSound?.play()
    }

    static func playStop() {
        stopSound?.stop()
        stopSound?.play()
    }
}
