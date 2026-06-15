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

struct SummarizerRequest: Identifiable {
    let id = UUID()
    let job: TranscriptionJob
    let record: TranscriptRecord
}
