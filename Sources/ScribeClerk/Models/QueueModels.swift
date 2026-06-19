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

struct PublishRequestItem: Equatable {
    let recordingID: String
    let variantID: String
}

struct PublishRequest: Identifiable {
    let id = UUID()
    let items: [PublishRequestItem]

    init(recordingID: String, variantID: String) {
        self.items = [PublishRequestItem(recordingID: recordingID, variantID: variantID)]
    }

    init(items: [PublishRequestItem]) {
        self.items = items
    }
}
