import Foundation

enum WhisperVAD {
    static let modelFileName = "ggml-silero-v6.2.0.bin"

    static var modelURL: URL {
        WhisperModelCatalog.modelsDirectory.appendingPathComponent(modelFileName)
    }

    static var isConfigured: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    static var setupHint: String {
        "Voice activity detection needs \(modelFileName) in \(WhisperModelCatalog.modelsDirectory.path)."
    }
}
