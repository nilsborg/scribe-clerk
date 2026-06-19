import Foundation

enum TranscriptionFileParserError: LocalizedError {
    case unreadableFile
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The transcription file could not be read."
        case .emptyTranscript:
            return "The transcription file did not contain any text."
        }
    }
}

struct ParsedTranscription {
    let text: String
    let durationSeconds: TimeInterval?
    let sourceFormat: String
}

enum TranscriptionFileParser {
    private struct Cue: Comparable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String

        static func < (lhs: Cue, rhs: Cue) -> Bool {
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }
    }

    static func parse(url: URL) throws -> ParsedTranscription {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw TranscriptionFileParserError.unreadableFile
        }
        return try parse(contents: contents, fileExtension: url.pathExtension)
    }

    static func parse(contents: String, fileExtension: String) throws -> ParsedTranscription {
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionFileParserError.emptyTranscript
        }

        let ext = fileExtension.lowercased()
        if ext == "srt" {
            return try parseSRT(trimmed)
        }

        if ext == "vtt" || trimmed.uppercased().hasPrefix("WEBVTT") {
            return try parseVTT(trimmed)
        }

        return ParsedTranscription(
            text: decodeEntities(trimmed),
            durationSeconds: nil,
            sourceFormat: "txt"
        )
    }

    private static func parseVTT(_ contents: String) throws -> ParsedTranscription {
        let cues = try parseCues(
            from: contents,
            timestampPattern: #"^(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s+-->\s+(\d{2}):(\d{2}):(\d{2})\.(\d{3})"#,
            fractionalSeparator: "."
        )
        return try makeParsedTranscription(from: cues, sourceFormat: "vtt")
    }

    private static func parseSRT(_ contents: String) throws -> ParsedTranscription {
        let cues = try parseCues(
            from: contents,
            timestampPattern: #"^(\d{2}):(\d{2}):(\d{2}),(\d{3})\s+-->\s+(\d{2}):(\d{2}):(\d{2}),(\d{3})"#,
            fractionalSeparator: ","
        )
        return try makeParsedTranscription(from: cues, sourceFormat: "srt")
    }

    private static func parseCues(
        from contents: String,
        timestampPattern: String,
        fractionalSeparator: String
    ) throws -> [Cue] {
        let regex = try NSRegularExpression(pattern: timestampPattern)
        let lines = contents.components(separatedBy: "\n")
        var cues: [Cue] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            guard !line.isEmpty else { continue }

            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: nsRange) else { continue }

            let start = timestampSeconds(from: match, in: line, baseIndex: 1, fractionalSeparator: fractionalSeparator)
            let end = timestampSeconds(from: match, in: line, baseIndex: 5, fractionalSeparator: fractionalSeparator)

            var textLines: [String] = []
            while index < lines.count {
                let textLine = lines[index]
                let trimmedLine = textLine.trimmingCharacters(in: .whitespacesAndNewlines)
                index += 1
                if trimmedLine.isEmpty {
                    if textLines.isEmpty {
                        continue
                    }
                    break
                }
                textLines.append(trimmedLine)
            }

            let text = formatCueText(textLines)
            guard !text.isEmpty else { continue }
            cues.append(Cue(start: start, end: end, text: text))
        }

        guard !cues.isEmpty else {
            throw TranscriptionFileParserError.emptyTranscript
        }

        return cues.sorted()
    }

    private static func makeParsedTranscription(from cues: [Cue], sourceFormat: String) throws -> ParsedTranscription {
        let text = cues.map(\.text).joined(separator: "\n")
        let duration = cues.map(\.end).max()
        return ParsedTranscription(
            text: text,
            durationSeconds: duration,
            sourceFormat: sourceFormat
        )
    }

    private static func timestampSeconds(
        from match: NSTextCheckingResult,
        in line: String,
        baseIndex: Int,
        fractionalSeparator: String
    ) -> TimeInterval {
        func component(_ index: Int) -> Int {
            guard let range = Range(match.range(at: index), in: line) else { return 0 }
            return Int(line[range]) ?? 0
        }

        let hours = component(baseIndex)
        let minutes = component(baseIndex + 1)
        let seconds = component(baseIndex + 2)
        let fraction = component(baseIndex + 3)
        let divisor: Double = fractionalSeparator == "," ? 1_000 : 1_000
        return TimeInterval(hours * 3_600 + minutes * 60 + seconds) + TimeInterval(fraction) / divisor
    }

    private static func formatCueText(_ lines: [String]) -> String {
        let joined = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !joined.isEmpty else { return "" }

        let speakerPattern = #"^<v\s+([^>]+)>(.*)</v>$"#
        if let regex = try? NSRegularExpression(pattern: speakerPattern),
           let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
           let speakerRange = Range(match.range(at: 1), in: joined),
           let textRange = Range(match.range(at: 2), in: joined) {
            let speaker = decodeEntities(String(joined[speakerRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            let text = decodeEntities(String(joined[textRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            guard !text.isEmpty else { return "" }
            return speaker.isEmpty ? text : "\(speaker): \(text)"
        }

        return decodeEntities(joined)
    }

    private static func decodeEntities(_ value: String) -> String {
        let data = Data("<span>\(value)</span>".utf8)
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else {
            return value
        }
        return attributed.string
    }
}
