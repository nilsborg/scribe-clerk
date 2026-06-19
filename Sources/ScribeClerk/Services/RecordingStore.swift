import Foundation

struct RecordingStore {
    static let shared = RecordingStore()

    private let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let metadataFileName = "recording.json"

    init() {
        rootDirectory = AppSupportPaths.directory(named: "recordings")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func recordingDirectory(for id: String) -> URL {
        rootDirectory.appendingPathComponent(id, isDirectory: true)
    }

    func metadataURL(for id: String) -> URL {
        recordingDirectory(for: id).appendingPathComponent(metadataFileName)
    }

    func audioURL(for record: RecordingRecord) -> URL? {
        guard let audioFileName = record.audioFileName else { return nil }
        return recordingDirectory(for: record.id).appendingPathComponent(audioFileName)
    }

    func transcriptURL(for record: RecordingRecord) -> URL? {
        guard let transcriptFileName = record.transcriptFileName else { return nil }
        return recordingDirectory(for: record.id).appendingPathComponent(transcriptFileName)
    }

    func summaryURL(for record: RecordingRecord, variant: SummaryVariantRecord) -> URL? {
        guard let markdownFileName = variant.markdownFileName else { return nil }
        return recordingDirectory(for: record.id)
            .appendingPathComponent("summaries", isDirectory: true)
            .appendingPathComponent(markdownFileName)
    }

    func summariesDirectory(for id: String) -> URL {
        recordingDirectory(for: id).appendingPathComponent("summaries", isDirectory: true)
    }

    func load(id: String) -> RecordingRecord? {
        let url = metadataURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(RecordingRecord.self, from: data)
    }

    func allRecordings() -> [RecordingRecord] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return directories.compactMap { directory -> RecordingRecord? in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return load(id: directory.lastPathComponent)
        }
        .sorted { $0.importedAt > $1.importedAt }
    }

    func save(_ record: RecordingRecord) throws {
        let directory = recordingDirectory(for: record.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(record)
        try data.write(to: metadataURL(for: record.id), options: .atomic)
    }

    func writeTranscript(_ text: String, for record: inout RecordingRecord) throws -> URL {
        let fileName = record.transcriptFileName ?? "transcript.txt"
        let url = recordingDirectory(for: record.id).appendingPathComponent(fileName)
        try text.write(to: url, atomically: true, encoding: .utf8)
        record.transcriptFileName = fileName
        return url
    }

    func readTranscript(for record: RecordingRecord) -> String? {
        guard let url = transcriptURL(for: record) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func writeSummary(_ markdown: String, for record: inout RecordingRecord, variant: inout SummaryVariantRecord) throws -> URL {
        let summariesDir = summariesDirectory(for: record.id)
        try FileManager.default.createDirectory(at: summariesDir, withIntermediateDirectories: true)

        let fileName = variant.markdownFileName ?? "\(variant.id).md"
        let url = summariesDir.appendingPathComponent(fileName)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        variant.markdownFileName = fileName
        return url
    }

    func readSummary(for record: RecordingRecord, variant: SummaryVariantRecord) -> String? {
        guard let url = summaryURL(for: record, variant: variant) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func delete(id: String) {
        try? FileManager.default.removeItem(at: recordingDirectory(for: id))
    }

    func existingContentHashes() -> Set<String> {
        Set(allRecordings().map(\.contentHash))
    }

    func recording(withContentHash hash: String) -> RecordingRecord? {
        allRecordings().first { $0.contentHash == hash }
    }
}
