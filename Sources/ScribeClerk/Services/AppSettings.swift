import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let whisperBinaryPath = "whisperBinaryPath"
        static let diarizationBinaryPath = "diarizationBinaryPath"
        static let defaultModelPath = "defaultModelPath"
        static let voiceActivityDetectionEnabled = "voiceActivityDetectionEnabled"
        static let transcriptionVocabulary = "transcriptionVocabulary"
        static let denoBinaryPath = "denoBinaryPath"
        static let adapterEnvPath = "adapterEnvPath"
        static let defaultSummarizerFlow = "defaultSummarizerFlow"
        static let legacySummarizerRepoPath = "summarizerRepoPath"
    }

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

    var diarizationBinaryPath: String {
        get {
            defaults.string(forKey: Keys.diarizationBinaryPath)
                ?? "/opt/homebrew/bin/sherpa-onnx-offline-speaker-diarization"
        }
        set {
            defaults.set(newValue, forKey: Keys.diarizationBinaryPath)
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

    var voiceActivityDetectionEnabled: Bool {
        get {
            defaults.object(forKey: Keys.voiceActivityDetectionEnabled) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.voiceActivityDetectionEnabled)
        }
    }

    var transcriptionVocabulary: String {
        get {
            defaults.string(forKey: Keys.transcriptionVocabulary) ?? ""
        }
        set {
            defaults.set(newValue, forKey: Keys.transcriptionVocabulary)
        }
    }

    var transcriptionPrompt: String? {
        let vocabulary = transcriptionVocabulary
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return vocabulary.isEmpty ? nil : vocabulary
    }

    var denoBinaryPath: String {
        get {
            defaults.string(forKey: Keys.denoBinaryPath) ?? Self.defaultDenoBinaryPath
        }
        set {
            defaults.set(newValue, forKey: Keys.denoBinaryPath)
        }
    }

    var adapterEnvPath: String {
        get {
            AppSupportPaths.resolvedAdapterEnvPath()
        }
        set {
            defaults.set(newValue, forKey: Keys.adapterEnvPath)
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

    func defaultTranscriptionOptions() -> TranscriptionOptions {
        let models = WhisperModelCatalog.availableModels(defaultPath: defaultModelPath)
        let modelPath = WhisperModelCatalog.resolvedDefaultModelPath(
            configuredPath: defaultModelPath,
            availablePaths: models
        )

        return TranscriptionOptions(
            language: "auto",
            modelPath: modelPath
        )
    }
}
