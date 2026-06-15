import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let whisperBinaryPath = "whisperBinaryPath"
        static let defaultModelPath = "defaultModelPath"
        static let summarizerRepoPath = "summarizerRepoPath"
        static let denoBinaryPath = "denoBinaryPath"
        static let defaultSummarizerFlow = "defaultSummarizerFlow"
    }

    static let defaultSummarizerRepoPath = "/Users/nilsborg/Repos/meeting-summaries-to-notion"
    static let defaultDenoBinaryPath = "/opt/homebrew/bin/deno"

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

    var summarizerRepoPath: String {
        get {
            defaults.string(forKey: Keys.summarizerRepoPath) ?? Self.defaultSummarizerRepoPath
        }
        set {
            defaults.set(newValue, forKey: Keys.summarizerRepoPath)
        }
    }

    var denoBinaryPath: String {
        get {
            defaults.string(forKey: Keys.denoBinaryPath) ?? Self.defaultDenoBinaryPath
        }
        set {
            defaults.set(newValue, forKey: Keys.denoBinaryPath)
        }
    }

    var defaultSummarizerFlow: SummarizerFlow {
        get {
            guard let raw = defaults.string(forKey: Keys.defaultSummarizerFlow),
                  let flow = SummarizerFlow(rawValue: raw) else {
                return .meeting
            }
            return flow
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.defaultSummarizerFlow)
        }
    }

    func defaultSummarizerOptions(for record: TranscriptRecord) -> SummarizerOptions {
        SummarizerOptions(
            flow: defaultSummarizerFlow,
            language: SummarizerLanguage.defaultFor(transcriptLanguage: record.language)
        )
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
