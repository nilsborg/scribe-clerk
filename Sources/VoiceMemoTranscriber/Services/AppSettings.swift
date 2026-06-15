import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let whisperBinaryPath = "whisperBinaryPath"
        static let defaultModelPath = "defaultModelPath"
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

    var defaultModelPath: String {
        get {
            if let value = defaults.string(forKey: Keys.defaultModelPath) {
                return value
            }

            if let legacy = defaults.string(forKey: "modelPath") {
                defaults.set(legacy, forKey: Keys.defaultModelPath)
                return legacy
            }

            return WhisperModelCatalog.preferredDefaultModelPath()
        }
        set {
            defaults.set(newValue, forKey: Keys.defaultModelPath)
        }
    }

    func defaultTranscriptionOptions() -> TranscriptionOptions {
        let models = WhisperModelCatalog.availableModels(defaultPath: defaultModelPath)
        let modelPath: String

        if let medium = models.first(where: {
            URL(fileURLWithPath: $0).lastPathComponent == WhisperModelCatalog.preferredModelFileName
        }) {
            modelPath = medium
        } else if models.contains(defaultModelPath) {
            modelPath = defaultModelPath
        } else {
            modelPath = models.first ?? WhisperModelCatalog.preferredDefaultModelPath()
        }

        return TranscriptionOptions(
            language: "auto",
            modelPath: modelPath
        )
    }
}
