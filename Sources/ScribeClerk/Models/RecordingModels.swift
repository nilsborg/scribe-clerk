import Foundation

enum RecordingSource: String, Codable, CaseIterable {
    case inbox
    case dragDrop = "drag-drop"
    case filePicker = "file-picker"
    case transcriptImport = "transcript-import"

    var label: String {
        switch self {
        case .inbox:
            return "Inbox"
        case .dragDrop:
            return "Drag & Drop"
        case .filePicker:
            return "File Picker"
        case .transcriptImport:
            return "Imported Transcript"
        }
    }
}

enum RecordingTranscriptionStatus: String, Codable {
    case notStarted
    case queued
    case inProgress
    case completed
    case failed
}

enum SummaryVariantStatus: String, Codable {
    case notStarted
    case queued
    case generating
    case ready
    case publishing
    case published
    case failed
    case stale
}

struct PublishAttempt: Codable, Identifiable, Equatable {
    let id: String
    let attemptedAt: Date
    var success: Bool
    var destinationType: String
    var destinationURL: String?
    var errorMessage: String?

    init(
        id: String = UUID().uuidString,
        attemptedAt: Date = Date(),
        success: Bool,
        destinationType: String = "notion",
        destinationURL: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.attemptedAt = attemptedAt
        self.success = success
        self.destinationType = destinationType
        self.destinationURL = destinationURL
        self.errorMessage = errorMessage
    }
}

struct SummaryVariantRecord: Codable, Identifiable, Equatable {
    var flow: SummarizerFlow
    var language: SummarizerLanguage
    var status: SummaryVariantStatus
    var markdownFileName: String?
    var title: String?
    var generatedAt: Date?
    var errorMessage: String?
    var publishAttempts: [PublishAttempt]

    var id: String {
        Self.variantKey(flow: flow, language: language)
    }

    var options: SummarizerOptions {
        SummarizerOptions(flow: flow, language: language)
    }

    static func variantKey(flow: SummarizerFlow, language: SummarizerLanguage) -> String {
        "\(flow.rawValue)-\(language.rawValue)"
    }

    static func make(options: SummarizerOptions) -> SummaryVariantRecord {
        SummaryVariantRecord(
            flow: options.flow,
            language: options.language,
            status: .notStarted,
            markdownFileName: nil,
            title: nil,
            generatedAt: nil,
            errorMessage: nil,
            publishAttempts: []
        )
    }
}

struct RecordingRecord: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var importedAt: Date
    var recordedAt: Date?
    var source: RecordingSource
    var contentHash: String
    var audioFileName: String?
    var audioDurationSeconds: TimeInterval?
    var transcriptionStatus: RecordingTranscriptionStatus
    var transcriptionError: String?
    var transcriptionLanguage: String?
    var transcriptionModelPath: String?
    var transcribedAt: Date?
    var transcriptFileName: String?
    var titleGeneratedAt: Date?
    var summaryVariants: [SummaryVariantRecord]

    var displayDate: Date {
        recordedAt ?? importedAt
    }

    var preferredSummarizerLanguage: SummarizerLanguage {
        SummarizerLanguage.fromTranscriptionLanguage(transcriptionLanguage)
    }

    /// LLM-generated title from transcription; nil until title generation completes.
    var generatedTitle: String? {
        titleGeneratedAt != nil ? title : nil
    }

    var formattedAudioDuration: String? {
        AudioDuration.formatted(seconds: audioDurationSeconds)
    }

    var hasAudio: Bool {
        audioFileName != nil
    }

    func resolvedAudioDuration(from audioURL: URL?) -> String? {
        if let formattedAudioDuration {
            return formattedAudioDuration
        }
        guard let audioURL else { return nil }
        return AudioDuration.formatted(for: audioURL)
    }

    func transcriptionOptions(defaultModelPath: String) -> TranscriptionOptions? {
        guard let transcriptionLanguage, let transcriptionModelPath else { return nil }
        return TranscriptionOptions(language: transcriptionLanguage, modelPath: transcriptionModelPath)
    }

    func variant(for options: SummarizerOptions) -> SummaryVariantRecord? {
        summaryVariants.first { $0.flow == options.flow && $0.language == options.language }
    }

    mutating func upsertVariant(_ variant: SummaryVariantRecord) {
        if let index = summaryVariants.firstIndex(where: { $0.id == variant.id }) {
            summaryVariants[index] = variant
        } else {
            summaryVariants.append(variant)
        }
    }

    mutating func markSummariesStale() {
        for index in summaryVariants.indices where summaryVariants[index].status == .ready || summaryVariants[index].status == .published {
            summaryVariants[index].status = .stale
        }
    }
}

struct InboxItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let displayName: String
    let modifiedAt: Date
    let contentHash: String
    let duration: TimeInterval?

    var formattedDuration: String? {
        AudioDuration.formatted(seconds: duration)
    }
}

enum RecordingFilterSource: String, CaseIterable, Identifiable {
    case all
    case inbox
    case dragDrop = "drag-drop"
    case filePicker = "file-picker"
    case transcriptImport = "transcript-import"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All Sources"
        case .inbox:
            return "Inbox"
        case .dragDrop:
            return "Drag & Drop"
        case .filePicker:
            return "File Picker"
        case .transcriptImport:
            return "Imported Transcripts"
        }
    }
}

enum RecordingFilterStatus: String, CaseIterable, Identifiable {
    case all
    case imported
    case transcribed
    case summarized
    case published

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All Status"
        case .imported:
            return "Imported"
        case .transcribed:
            return "Transcribed"
        case .summarized:
            return "Summarized"
        case .published:
            return "Published"
        }
    }
}
