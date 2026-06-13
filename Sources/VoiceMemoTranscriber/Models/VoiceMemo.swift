import Foundation

struct VoiceMemo: Identifiable, Hashable {
    let id: Int64
    let uniqueID: String
    let title: String
    let recordedAt: Date
    let duration: TimeInterval
    let audioURL: URL

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        Self.dateFormatter.string(from: recordedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

enum TranscriptionStatus: Equatable {
    case notStarted
    case inProgress
    case completed(String)
    case failed(String)
}
