import Foundation

struct BulkRecordingActions {
    struct Availability {
        var transcribeIDs: [String] = []
        var summarizeIDs: [String] = []
        var resummarizeIDs: [String] = []
        var publishItems: [PublishRequestItem] = []
        var republishItems: [PublishRequestItem] = []
    }

    static func availability(for recordings: [RecordingRecord]) -> Availability {
        var result = Availability()

        for recording in recordings {
            if recording.transcriptionStatus != .inProgress,
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

            if let variant = leadPublishableVariant(in: recording) {
                let item = PublishRequestItem(recordingID: recording.id, variantID: variant.id)
                if variant.status == .published {
                    result.republishItems.append(item)
                } else {
                    result.publishItems.append(item)
                }
            }
        }

        return result
    }

    private static func isSummaryJobActive(_ recording: RecordingRecord) -> Bool {
        recording.summaryVariants.contains {
            $0.status == .queued || $0.status == .generating || $0.status == .publishing
        }
    }

    private static func needsFirstSummary(_ recording: RecordingRecord) -> Bool {
        recording.summaryVariants.isEmpty
            || recording.summaryVariants.allSatisfy {
                $0.status == .notStarted || ($0.status == .failed && $0.markdownFileName == nil)
            }
    }

    private static func leadPublishableVariant(in recording: RecordingRecord) -> SummaryVariantRecord? {
        if let published = recording.summaryVariants.first(where: { $0.status == .published }) {
            return published
        }
        if let ready = recording.summaryVariants.first(where: {
            [.ready, .stale, .failed].contains($0.status)
        }) {
            return ready
        }
        return nil
    }
}
