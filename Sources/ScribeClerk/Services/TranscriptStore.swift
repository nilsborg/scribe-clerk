import Foundation

struct TranscriptStore {
    static let shared = TranscriptStore()

    private let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        rootDirectory = AppSupportPaths.directory(named: "transcripts")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func record(for key: String) -> TranscriptRecord? {
        let jsonURL = jsonFileURL(for: key)
        if let data = try? Data(contentsOf: jsonURL),
           let record = try? decoder.decode(TranscriptRecord.self, from: data) {
            return record
        }

        let legacyURL = legacyTextFileURL(for: key)
        guard let text = try? String(contentsOf: legacyURL, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return TranscriptRecord(
            text: text,
            language: "unknown",
            modelPath: "unknown",
            createdAt: legacyModificationDate(for: legacyURL) ?? .distantPast,
            sourceURLString: nil,
            sourceName: nil
        )
    }

    func allRecords() -> [(key: String, record: TranscriptRecord)] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (String, TranscriptRecord)? in
                let key = url.deletingPathExtension().lastPathComponent
                guard let record = record(for: key) else { return nil }
                return (key, record)
            }
    }

    func save(_ record: TranscriptRecord, for key: String) throws {
        let data = try encoder.encode(record)
        try data.write(to: jsonFileURL(for: key), options: .atomic)

        let legacyURL = legacyTextFileURL(for: key)
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    func delete(for key: String) {
        try? FileManager.default.removeItem(at: jsonFileURL(for: key))
        try? FileManager.default.removeItem(at: legacyTextFileURL(for: key))
    }

    private func jsonFileURL(for key: String) -> URL {
        rootDirectory.appendingPathComponent("\(key).json")
    }

    private func legacyTextFileURL(for key: String) -> URL {
        rootDirectory.appendingPathComponent("\(key).txt")
    }

    private func legacyModificationDate(for url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
