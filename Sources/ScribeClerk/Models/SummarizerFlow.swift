import Foundation

enum SummarizerFlow: String, CaseIterable, Identifiable {
    case meeting
    case projectUpdates = "project-updates"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meeting:
            return "Meeting notes"
        case .projectUpdates:
            return "Project updates"
        }
    }
}

enum SummarizerLanguage: String, CaseIterable, Identifiable {
    case english
    case german

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english:
            return "English"
        case .german:
            return "German"
        }
    }

    static func defaultFor(transcriptLanguage: String) -> SummarizerLanguage {
        transcriptLanguage.lowercased().hasPrefix("de") ? .german : .english
    }
}

struct SummarizerOptions: Equatable {
    var flow: SummarizerFlow
    var language: SummarizerLanguage
}

struct SummarizerRequestItem: Equatable {
    let job: TranscriptionJob
    let record: TranscriptRecord
}

struct SummarizerRequest: Identifiable {
    let id = UUID()
    let items: [SummarizerRequestItem]

    init(job: TranscriptionJob, record: TranscriptRecord) {
        self.items = [SummarizerRequestItem(job: job, record: record)]
    }

    init(items: [SummarizerRequestItem]) {
        self.items = items
    }

    var title: String {
        if items.count == 1 {
            return items[0].job.displayName
        }
        return "\(items.count) Transcripts"
    }
}
