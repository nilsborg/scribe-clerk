import Foundation

struct WhisperModelCatalog {
    static let modelsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("whisper-models", isDirectory: true)

    static let preferredModelFileName = "ggml-medium.bin"

    private static let knownModels: [(fileName: String, label: String, sortOrder: Int)] = [
        ("ggml-tiny.bin", "Tiny", 10),
        ("ggml-tiny.en.bin", "Tiny (English)", 11),
        ("ggml-base.bin", "Base", 20),
        ("ggml-base.en.bin", "Base (English)", 21),
        ("ggml-small.bin", "Small", 30),
        ("ggml-small.en.bin", "Small (English)", 31),
        ("ggml-medium.bin", "Medium (default)", 40),
        ("ggml-medium.en.bin", "Medium (English)", 41),
        ("ggml-large-v3-turbo.bin", "Large v3 Turbo", 50),
        ("ggml-large-v3.bin", "Large v3", 51),
        ("ggml-large-v2.bin", "Large v2", 52),
        ("ggml-large-v1.bin", "Large v1", 53),
        ("ggml-large.bin", "Large", 54),
    ]

    static func preferredDefaultModelPath() -> String {
        let preferred = modelsDirectory.appendingPathComponent(preferredModelFileName).path
        if FileManager.default.fileExists(atPath: preferred) {
            return preferred
        }

        let fallbackNames = [
            "ggml-large-v3-turbo.bin",
            "ggml-small.bin",
            "ggml-base.bin",
            "ggml-large-v3.bin",
            "ggml-large.bin",
        ]
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

        if let files = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        ) {
            models = files
                .filter { $0.pathExtension.lowercased() == "bin" }
                .map(\.path)
        }

        if FileManager.default.fileExists(atPath: defaultPath), !models.contains(defaultPath) {
            models.append(defaultPath)
        }

        return models.sorted(by: sortPaths)
    }

    static func displayName(for path: String) -> String {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        if let known = knownModels.first(where: { $0.fileName == fileName }) {
            return known.label
        }
        return fileName
    }

    private static func sortPaths(_ lhs: String, _ rhs: String) -> Bool {
        let leftName = URL(fileURLWithPath: lhs).lastPathComponent
        let rightName = URL(fileURLWithPath: rhs).lastPathComponent
        let leftOrder = knownModels.first(where: { $0.fileName == leftName })?.sortOrder ?? 999
        let rightOrder = knownModels.first(where: { $0.fileName == rightName })?.sortOrder ?? 999

        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }

        return leftName.localizedStandardCompare(rightName) == .orderedAscending
    }
}
