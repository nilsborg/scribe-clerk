import Foundation

struct TranscriptionOptions: Equatable {
    var language: String
    var modelPath: String
}

struct TranscriptRecord: Codable, Equatable {
    let text: String
    let language: String
    let modelPath: String
    let createdAt: Date
    let sourceURLString: String?
    let sourceName: String?

    var sourceURL: URL? {
        guard let sourceURLString else { return nil }
        return URL(string: sourceURLString)
    }

    var modelName: String {
        URL(fileURLWithPath: modelPath).lastPathComponent
    }

    var optionsSummary: String {
        "Language: \(TranscriptionLanguageOption.label(for: language)) · Model: \(modelName)"
    }

    func withSource(url: URL, name: String) -> TranscriptRecord {
        TranscriptRecord(
            text: text,
            language: language,
            modelPath: modelPath,
            createdAt: createdAt,
            sourceURLString: url.absoluteString,
            sourceName: name
        )
    }
}
