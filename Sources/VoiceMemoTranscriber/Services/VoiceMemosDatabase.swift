import Foundation
import SQLite3

enum VoiceMemosDatabaseError: LocalizedError {
    case databaseNotFound(URL)
    case openFailed(URL, String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let url):
            return "Voice Memos database not found at \(url.path)."
        case .openFailed(let url, let message):
            return "Could not open \(url.lastPathComponent): \(message)"
        case .queryFailed(let message):
            return "Failed to read Voice Memos: \(message)"
        }
    }

    var recoverySuggestion: String? {
        "Grant Full Disk Access to Voice Memo Transcriber in System Settings > Privacy & Security > Full Disk Access, then restart the app."
    }
}

struct VoiceMemosDatabase {
    static let recordingsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings")

    static let databaseURL = recordingsDirectory.appendingPathComponent("CloudRecordings.db")

    func fetchRecordings(includeDeleted: Bool = false) throws -> [VoiceMemo] {
        guard FileManager.default.fileExists(atPath: Self.databaseURL.path) else {
            throw VoiceMemosDatabaseError.databaseNotFound(Self.databaseURL)
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let openResult = sqlite3_open_v2(Self.databaseURL.path, &database, flags, nil)
        guard openResult == SQLITE_OK, let database else {
            let message = String(cString: sqlite3_errmsg(database))
            sqlite3_close(database)
            throw VoiceMemosDatabaseError.openFailed(Self.databaseURL, message)
        }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT
            Z_PK,
            ZUNIQUEID,
            ZENCRYPTEDTITLE,
            ZCUSTOMLABEL,
            ZCUSTOMLABELFORSORTING,
            ZDATE,
            ZDURATION,
            ZPATH
        FROM ZCLOUDRECORDING
        WHERE (? = 1 OR ZEVICTIONDATE IS NULL)
        ORDER BY ZDATE DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw VoiceMemosDatabaseError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, includeDeleted ? 1 : 0)

        var recordings: [VoiceMemo] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let uniqueID = columnText(statement, 1) ?? UUID().uuidString
            let encryptedTitle = columnText(statement, 2)
            let customLabel = columnText(statement, 3)
            let customLabelForSorting = columnText(statement, 4)
            let coreDataDate = sqlite3_column_double(statement, 5)
            let duration = sqlite3_column_double(statement, 6)
            let path = columnText(statement, 7) ?? "\(uniqueID).m4a"

            let recordedAt = Date(timeIntervalSince1970: coreDataDate + 978_307_200)
            let title = Self.displayTitle(
                encryptedTitle: encryptedTitle,
                customLabel: customLabel,
                customLabelForSorting: customLabelForSorting,
                recordedAt: recordedAt
            )
            let audioURL = Self.recordingsDirectory.appendingPathComponent(path)

            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                continue
            }

            recordings.append(
                VoiceMemo(
                    id: id,
                    uniqueID: uniqueID,
                    title: title,
                    recordedAt: recordedAt,
                    duration: duration,
                    audioURL: audioURL
                )
            )
        }

        return recordings
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    /// Voice Memos stores the visible title in `ZENCRYPTEDTITLE`. `ZCUSTOMLABEL` is usually
    /// an ISO timestamp string, not the name shown in the app.
    private static func displayTitle(
        encryptedTitle: String?,
        customLabel: String?,
        customLabelForSorting: String?,
        recordedAt: Date
    ) -> String {
        for candidate in [encryptedTitle, customLabelForSorting, customLabel] {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  isReadableTitle(trimmed) else {
                continue
            }
            return trimmed
        }

        return defaultTitle(for: recordedAt)
    }

    private static func isReadableTitle(_ value: String) -> Bool {
        guard !looksLikeISODate(value) else { return false }

        let printableScalars = value.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || CharacterSet.whitespaces.contains($0)
                || CharacterSet.punctuationCharacters.contains($0)
        }

        return !printableScalars.isEmpty
    }

    private static func looksLikeISODate(_ value: String) -> Bool {
        isoDateFormatter.date(from: value) != nil
            || isoDateFormatterWithoutFractionalSeconds.date(from: value) != nil
    }

    private static func defaultTitle(for date: Date) -> String {
        defaultTitleFormatter.string(from: date)
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoDateFormatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let defaultTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
