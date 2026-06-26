import Foundation

enum SummarizerFlow: String, CaseIterable, Identifiable, Codable {
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

enum SummarizerLanguage: String, CaseIterable, Identifiable, Codable {
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

    static func fromTranscriptionLanguage(_ code: String?) -> SummarizerLanguage {
        guard let code else { return .english }

        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "auto", normalized != "unknown" else {
            return .english
        }

        return defaultFor(transcriptLanguage: normalized)
    }
}

struct SummarizerOptions: Equatable, Hashable {
    var flow: SummarizerFlow
    var language: SummarizerLanguage
}
