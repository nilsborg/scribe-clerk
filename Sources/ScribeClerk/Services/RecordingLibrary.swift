import Foundation
import CryptoKit

enum RecordingLibraryError: LocalizedError {
    case unsupportedFile
    case importFailed(String)
    case duplicateFound(RecordingRecord)
    case trashFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "The selected file is not a supported audio or transcription format."
        case .importFailed(let message):
            return message
        case .duplicateFound(let existing):
            return "A recording with the same content already exists: “\(existing.title)”."
        case .trashFailed(let message):
            return message
        }
    }
}

struct RecordingImportResult {
    let record: RecordingRecord
    let wasDuplicate: Bool
}

struct RecordingLibrary {
    static let shared = RecordingLibrary()

    private let fileManager = FileManager.default
    private let store = RecordingStore.shared

    var inboxDirectory: URL {
        AppSupportPaths.directory(named: "inbox")
    }

    func inboxItems() -> [InboxItem] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: inboxDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files.compactMap { url -> InboxItem? in
            guard AudioFileFilter.isAudioFile(url) else { return nil }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let hash = (try? contentHash(for: url)) ?? url.lastPathComponent
            return InboxItem(
                id: url.standardizedFileURL.path,
                url: url,
                displayName: url.deletingPathExtension().lastPathComponent,
                modifiedAt: values?.contentModificationDate ?? .distantPast,
                contentHash: hash,
                duration: AudioDuration.seconds(for: url)
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func addToInbox(_ urls: [URL]) {
        for url in AudioFileFilter.filter(urls) {
            _ = AudioInbox.add(url)
        }
    }

    func trashInboxItem(_ item: InboxItem) throws {
        guard fileManager.fileExists(atPath: item.url.path) else { return }
        do {
            try fileManager.trashItem(at: item.url, resultingItemURL: nil)
        } catch {
            throw RecordingLibraryError.trashFailed(error.localizedDescription)
        }
    }

    func importFromInbox(_ item: InboxItem, allowDuplicate: Bool = false) throws -> RecordingImportResult {
        try importAudio(
            from: item.url,
            source: .inbox,
            title: item.displayName,
            moveOriginal: true,
            allowDuplicate: allowDuplicate
        )
    }

    func importAudioFiles(
        _ urls: [URL],
        source: RecordingSource,
        allowDuplicate: Bool = false
    ) throws -> [RecordingImportResult] {
        try urls.map { url in
            try importAudio(
                from: url,
                source: source,
                title: url.deletingPathExtension().lastPathComponent,
                moveOriginal: false,
                allowDuplicate: allowDuplicate
            )
        }
    }

    func importTranscriptionFiles(
        _ urls: [URL],
        source: RecordingSource,
        allowDuplicate: Bool = false
    ) throws -> [RecordingImportResult] {
        try urls.map { url in
            try importTranscription(
                from: url,
                source: source,
                title: url.deletingPathExtension().lastPathComponent,
                allowDuplicate: allowDuplicate
            )
        }
    }

    func importTranscription(
        from sourceURL: URL,
        source: RecordingSource,
        title: String,
        allowDuplicate: Bool
    ) throws -> RecordingImportResult {
        guard TranscriptionFileFilter.isTranscriptionFile(sourceURL) else {
            throw RecordingLibraryError.unsupportedFile
        }

        let parsed = try TranscriptionFileParser.parse(url: sourceURL)
        let hash = try contentHash(for: Data(parsed.text.utf8))
        if let existing = store.recording(withContentHash: hash), !allowDuplicate {
            throw RecordingLibraryError.duplicateFound(existing)
        }

        let id = UUID().uuidString
        let directory = store.recordingDirectory(for: id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var record = RecordingRecord(
            id: id,
            title: title,
            importedAt: Date(),
            recordedAt: fileModificationDate(for: sourceURL),
            source: source,
            contentHash: hash,
            audioFileName: nil,
            audioDurationSeconds: parsed.durationSeconds,
            transcriptionStatus: .completed,
            transcriptionError: nil,
            transcriptionLanguage: "unknown",
            transcriptionModelPath: "imported",
            transcribedAt: Date(),
            transcriptFileName: nil,
            summaryVariants: []
        )

        _ = try store.writeTranscript(parsed.text, for: &record)
        try store.save(record)
        return RecordingImportResult(record: record, wasDuplicate: false)
    }

    func importAudio(
        from sourceURL: URL,
        source: RecordingSource,
        title: String,
        moveOriginal: Bool,
        allowDuplicate: Bool
    ) throws -> RecordingImportResult {
        guard AudioFileFilter.isAudioFile(sourceURL) else {
            throw RecordingLibraryError.unsupportedFile
        }

        let hash = try contentHash(for: sourceURL)
        if let existing = store.recording(withContentHash: hash), !allowDuplicate {
            throw RecordingLibraryError.duplicateFound(existing)
        }

        let id = UUID().uuidString
        let directory = store.recordingDirectory(for: id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.isEmpty ? "audio" : sourceURL.pathExtension
        let audioFileName = "audio.\(ext)"
        let destination = directory.appendingPathComponent(audioFileName)

        if moveOriginal {
            try fileManager.moveItem(at: sourceURL, to: destination)
        } else {
            try fileManager.copyItem(at: sourceURL, to: destination)
        }

        let duration = AudioDuration.seconds(for: destination)

        let record = RecordingRecord(
            id: id,
            title: title,
            importedAt: Date(),
            recordedAt: fileModificationDate(for: sourceURL),
            source: source,
            contentHash: hash,
            audioFileName: audioFileName,
            audioDurationSeconds: duration,
            transcriptionStatus: .notStarted,
            transcriptionError: nil,
            transcriptionLanguage: nil,
            transcriptionModelPath: nil,
            transcribedAt: nil,
            transcriptFileName: nil,
            summaryVariants: []
        )

        try store.save(record)
        return RecordingImportResult(record: record, wasDuplicate: false)
    }

    func contentHash(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return try contentHash(for: data)
    }

    func contentHash(for data: Data) throws -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileModificationDate(for url: URL) -> Date? {
        try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
