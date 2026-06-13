import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let whisperBinaryPath = "whisperBinaryPath"
        static let modelPath = "modelPath"
        static let language = "language"
    }

    var whisperBinaryPath: String {
        get {
            defaults.string(forKey: Keys.whisperBinaryPath)
                ?? "/opt/homebrew/bin/whisper-cli"
        }
        set {
            defaults.set(newValue, forKey: Keys.whisperBinaryPath)
        }
    }

    var modelPath: String {
        get {
            defaults.string(forKey: Keys.modelPath)
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("whisper-models/ggml-small.bin")
                    .path
        }
        set {
            defaults.set(newValue, forKey: Keys.modelPath)
        }
    }

    var language: String {
        get {
            defaults.string(forKey: Keys.language) ?? "auto"
        }
        set {
            defaults.set(newValue, forKey: Keys.language)
        }
    }
}
