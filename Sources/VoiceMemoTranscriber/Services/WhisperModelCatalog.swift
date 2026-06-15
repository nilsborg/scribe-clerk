import Foundation

struct WhisperModelCatalog {
    static let modelsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("whisper-models", isDirectory: true)

    static let preferredModelFileName = "ggml-medium.bin"

    static func preferredDefaultModelPath() -> String {
        let preferred = modelsDirectory.appendingPathComponent(preferredModelFileName).path
        if FileManager.default.fileExists(atPath: preferred) {
            return preferred
        }

        let fallbackNames = ["ggml-small.bin", "ggml-base.bin", "ggml-large.bin"]
        for name in fallbackNames {
            let path = modelsDirectory.appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return preferred
    }

    static func availableModels(defaultPath: String) -> [String] {
        var models: [String] = []

        let preferred = preferredDefaultModelPath()
        if FileManager.default.fileExists(atPath: preferred) {
            models.append(preferred)
        }

        if FileManager.default.fileExists(atPath: defaultPath), !models.contains(defaultPath) {
            models.append(defaultPath)
        }

        if let files = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        ) {
            let discovered = files
                .filter { $0.pathExtension.lowercased() == "bin" }
                .map(\.path)
                .sorted()

            for path in discovered where !models.contains(path) {
                models.append(path)
            }
        }

        return models
    }

    static func displayName(for path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
