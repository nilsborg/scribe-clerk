import Foundation

struct QueuedTranscriptionItem: Equatable {
    let recordingID: String
    let options: TranscriptionOptions
}

struct QueuedSummaryItem: Equatable {
    let recordingID: String
    let options: SummarizerOptions
    let regenerate: Bool
}

struct DuplicateImportPrompt: Identifiable {
    enum ImportKind {
        case audio
        case transcription
    }

    let id = UUID()
    let existing: RecordingRecord
    let pendingURLs: [URL]
    let source: RecordingSource
    let importKind: ImportKind
}

struct SummaryRequest: Identifiable {
    let id = UUID()
    let recordingIDs: [String]
    let regenerate: Bool

    init(recordingID: String, regenerate: Bool) {
        self.recordingIDs = [recordingID]
        self.regenerate = regenerate
    }

    init(recordingIDs: [String], regenerate: Bool) {
        self.recordingIDs = recordingIDs
        self.regenerate = regenerate
    }
}
