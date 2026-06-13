import Foundation

struct TranscriptStore {
    static let shared = TranscriptStore()

    private let rootDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDirectory = appSupport.appendingPathComponent("VoiceMemoTranscriber/transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func transcript(for uniqueID: String) -> String? {
        let url = fileURL(for: uniqueID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func save(_ transcript: String, for uniqueID: String) throws {
        try transcript.write(to: fileURL(for: uniqueID), atomically: true, encoding: .utf8)
    }

    func hasTranscript(for uniqueID: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: uniqueID).path)
    }

    private func fileURL(for uniqueID: String) -> URL {
        rootDirectory.appendingPathComponent("\(uniqueID).txt")
    }
}
