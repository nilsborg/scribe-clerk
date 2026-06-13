import Foundation

@MainActor
final class VoiceMemoListViewModel: ObservableObject {
    @Published private(set) var memos: [VoiceMemo] = []
    @Published private(set) var statuses: [String: TranscriptionStatus] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isTranscribing = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    private let database = VoiceMemosDatabase()
    private let transcriber = WhisperTranscriber()
    private let transcriptStore = TranscriptStore.shared

    var filteredMemos: [VoiceMemo] {
        guard !searchText.isEmpty else { return memos }
        let query = searchText.lowercased()
        return memos.filter { memo in
            memo.title.lowercased().contains(query)
                || transcriptText(for: memo)?.lowercased().contains(query) == true
        }
    }

    var pendingCount: Int {
        memos.filter { status(for: $0) == .notStarted }.count
    }

    func loadMemos() async {
        isLoading = true
        errorMessage = nil

        do {
            let recordings = try database.fetchRecordings()
            memos = recordings

            var nextStatuses: [String: TranscriptionStatus] = [:]
            for memo in recordings {
                if let transcript = transcriptStore.transcript(for: memo.uniqueID) {
                    nextStatuses[memo.uniqueID] = .completed(transcript)
                } else {
                    nextStatuses[memo.uniqueID] = statuses[memo.uniqueID] ?? .notStarted
                }
            }
            statuses = nextStatuses
        } catch {
            errorMessage = [error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: "\n\n")
        }

        isLoading = false
    }

    func status(for memo: VoiceMemo) -> TranscriptionStatus {
        statuses[memo.uniqueID] ?? .notStarted
    }

    func transcriptText(for memo: VoiceMemo) -> String? {
        if case .completed(let text) = status(for: memo) {
            return text
        }
        return nil
    }

    func transcribe(_ memo: VoiceMemo) async {
        guard !isTranscribing else { return }

        isTranscribing = true
        statuses[memo.uniqueID] = .inProgress
        errorMessage = nil

        do {
            let transcript = try await transcriber.transcribe(audioURL: memo.audioURL)
            try transcriptStore.save(transcript, for: memo.uniqueID)
            statuses[memo.uniqueID] = .completed(transcript)
        } catch {
            statuses[memo.uniqueID] = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }

        isTranscribing = false
    }

    func transcribePending() async {
        for memo in memos where status(for: memo) == .notStarted {
            await transcribe(memo)
        }
    }

    func revealInFinder(_ memo: VoiceMemo) {
        NSWorkspace.shared.activateFileViewerSelecting([memo.audioURL])
    }
}

import AppKit
