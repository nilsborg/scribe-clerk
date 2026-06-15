import Foundation
import CryptoKit

struct TranscriptionJob: Identifiable, Equatable {
    let id: String
    let audioURL: URL
    let displayName: String
    let receivedAt: Date
    var status: TranscriptionStatus

    var formattedDate: String {
        Self.dateFormatter.string(from: receivedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func make(from url: URL) -> TranscriptionJob {
        TranscriptionJob(
            id: stableID(for: url),
            audioURL: url,
            displayName: url.deletingPathExtension().lastPathComponent,
            receivedAt: Date(),
            status: .notStarted
        )
    }

    static func stableID(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum TranscriptionStatus: Equatable {
    case notStarted
    case queued
    case inProgress
    case completed(TranscriptRecord)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .queued, .inProgress:
            return true
        default:
            return false
        }
    }

    var statusLabel: String {
        switch self {
        case .notStarted:
            return "Ready"
        case .queued:
            return "Queued"
        case .inProgress:
            return "Transcribing…"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        }
    }

    var statusIcon: String {
        switch self {
        case .notStarted:
            return "circle"
        case .queued:
            return "clock"
        case .inProgress:
            return "waveform"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}
