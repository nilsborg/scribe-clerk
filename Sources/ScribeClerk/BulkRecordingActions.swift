import Foundation

struct BulkRecordingActions {
    struct Availability {
        var transcribeIDs: [String] = []
        var summarizeIDs: [String] = []
        var resummarizeIDs: [String] = []
    }

    static func availability(for recordings: [RecordingRecord]) -> Availability {
        var result = Availability()

        for recording in recordings {
            if recording.hasAudio,
               recording.transcriptionStatus != .inProgress,
               recording.transcriptionStatus != .queued {
                result.transcribeIDs.append(recording.id)
            }

            guard recording.transcriptionStatus == .completed else { continue }
            guard !isSummaryJobActive(recording) else { continue }

            if needsFirstSummary(recording) {
                result.summarizeIDs.append(recording.id)
            } else if !recording.summaryVariants.isEmpty {
                result.resummarizeIDs.append(recording.id)
            }
        }

        return result
    }

    private static func isSummaryJobActive(_ recording: RecordingRecord) -> Bool {
        recording.summaryVariants.contains {
            $0.status == .queued || $0.status == .generating
        }
    }

    private static func needsFirstSummary(_ recording: RecordingRecord) -> Bool {
        recording.summaryVariants.isEmpty
            || recording.summaryVariants.allSatisfy {
                $0.status == .notStarted || ($0.status == .failed && $0.markdownFileName == nil)
            }
    }
}
