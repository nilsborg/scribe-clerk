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

struct QueuedPublishItem: Equatable {
    let recordingID: String
    let variantID: String
}

struct DuplicateImportPrompt: Identifiable {
    let id = UUID()
    let existing: RecordingRecord
    let pendingURLs: [URL]
    let source: RecordingSource
}

struct SummaryRequest: Identifiable {
    let id = UUID()
    let recordingID: String
    let regenerate: Bool
}

struct PublishRequest: Identifiable {
    let id = UUID()
    let recordingID: String
    let variantID: String
}
