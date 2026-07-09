import Foundation

/// A single timestamped chunk of transcript text, as emitted by whisper.cpp JSON.
struct TranscriptSegment: Equatable {
    /// Seconds from the start of the audio.
    let start: Double
    let end: Double
    let text: String

    /// Parses the `transcription` array from a whisper.cpp `-oj` JSON file.
    /// whisper.cpp reports `offsets.from`/`offsets.to` in milliseconds.
    static func parseWhisperJSON(at url: URL) throws -> [TranscriptSegment] {
        let data = try Data(contentsOf: url)
        let root = try JSONDecoder().decode(WhisperJSON.self, from: data)
        return root.transcription.compactMap { entry in
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(
                start: Double(entry.offsets.from) / 1000.0,
                end: Double(entry.offsets.to) / 1000.0,
                text: text
            )
        }
    }

    private struct WhisperJSON: Decodable {
        let transcription: [Entry]

        struct Entry: Decodable {
            let text: String
            let offsets: Offsets
        }

        struct Offsets: Decodable {
            let from: Int
            let to: Int
        }
    }
}
