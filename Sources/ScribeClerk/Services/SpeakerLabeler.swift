import Foundation

/// A "who spoke when" interval produced by the diarization pass.
struct SpeakerTurn: Equatable {
    /// Seconds from the start of the audio.
    let start: Double
    let end: Double
    /// Raw speaker id from the diarizer, e.g. "speaker_00".
    let speaker: String
}

/// Merges timestamped transcript segments with diarization turns into a
/// speaker-labelled transcript.
enum SpeakerLabeler {
    static func label(segments: [TranscriptSegment], with turns: [SpeakerTurn]) -> String {
        guard !segments.isEmpty else { return "" }

        // Stable "speaker_00" -> "Speaker 1" mapping in first-appearance order.
        var displayNames: [String: String] = [:]
        func displayName(for speaker: String) -> String {
            if let existing = displayNames[speaker] { return existing }
            let name = "Speaker \(displayNames.count + 1)"
            displayNames[speaker] = name
            return name
        }

        var blocks: [(speaker: String, text: String)] = []

        for segment in segments {
            let speaker = bestSpeaker(for: segment, among: turns)

            // Coalesce consecutive segments from the same speaker into one block.
            if let speaker, var last = blocks.last, last.speaker == speaker {
                last.text += " " + segment.text
                blocks[blocks.count - 1] = last
            } else if let speaker {
                blocks.append((speaker, segment.text))
            } else if var last = blocks.last {
                // No diarization match (rare): append to the previous block.
                last.text += " " + segment.text
                blocks[blocks.count - 1] = last
            } else {
                blocks.append((turns.first?.speaker ?? "speaker_00", segment.text))
            }
        }

        return blocks
            .map { "\(displayName(for: $0.speaker)): \($0.text)" }
            .joined(separator: "\n\n")
    }

    /// The speaker whose turn overlaps this segment the most, or the nearest
    /// turn if there is no overlap at all.
    private static func bestSpeaker(for segment: TranscriptSegment, among turns: [SpeakerTurn]) -> String? {
        guard !turns.isEmpty else { return nil }

        var bestOverlap = 0.0
        var bestSpeaker: String?
        for turn in turns {
            let overlap = min(segment.end, turn.end) - max(segment.start, turn.start)
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeaker = turn.speaker
            }
        }
        if let bestSpeaker { return bestSpeaker }

        // No overlap: fall back to the turn closest to the segment's midpoint.
        let mid = (segment.start + segment.end) / 2
        return turns.min(by: { distance(from: mid, to: $0) < distance(from: mid, to: $1) })?.speaker
    }

    private static func distance(from time: Double, to turn: SpeakerTurn) -> Double {
        if time < turn.start { return turn.start - time }
        if time > turn.end { return time - turn.end }
        return 0
    }
}
