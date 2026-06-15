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
    case inProgress
    case completed(TranscriptRecord)
    case failed(String)
}
