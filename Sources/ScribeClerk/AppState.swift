import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var recordings: [RecordingRecord] = []
    @Published private(set) var inboxItems: [InboxItem] = []
    @Published var sidebarSelection: Set<String> = []
    @Published var searchText = ""
    @Published var filterSource: RecordingFilterSource = .all
    @Published var filterStatus: RecordingFilterStatus = .all
    @Published var pendingTranscriptionRequest: TranscriptionRequest?
    @Published var summaryRequest: SummaryRequest?
    @Published var publishRequest: PublishRequest?
    @Published var duplicateImportPrompt: DuplicateImportPrompt?
    @Published var errorMessage: String?
    @Published private(set) var whisperLogText = ""
    @Published private(set) var transcriptionProgress: Double?

    @Published private(set) var activeTranscriptionRecordingID: String?
    @Published private(set) var pendingTranscriptionCount = 0
    @Published private(set) var activeSummaryRecordingID: String?
    @Published private(set) var pendingSummaryCount = 0
    @Published private(set) var activePublishRecordingID: String?
    @Published private(set) var pendingPublishCount = 0

    private let transcriber = WhisperTranscriber()
    private let adapter = MeetingSummariesToNotionAdapter()
    private let library = RecordingLibrary.shared
    private let store = RecordingStore.shared

    private var transcriptionQueue: [QueuedTranscriptionItem] = []
    private var summaryQueue: [QueuedSummaryItem] = []
    private var publishQueue: [QueuedPublishItem] = []
    private var titleQueue: [String] = []
    private var transcriptionTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var titleTask: Task<Void, Never>?
    private var stopTranscriptionRequested = false
    private var stopSummaryRequested = false
    private var stopPublishRequested = false

    var isAnyJobActive: Bool {
        isTranscriptionActive || isSummaryActive || isPublishActive
    }

    var isTranscriptionActive: Bool {
        transcriptionTask != nil
    }

    var isSummaryActive: Bool {
        summaryTask != nil
    }

    var isPublishActive: Bool {
        publishTask != nil
    }

    var filteredRecordings: [RecordingRecord] {
        recordings.filter { record in
            matchesSearch(record) && matchesSource(record) && matchesStatus(record)
        }
    }

    var groupedRecordings: [RecordingSidebarSection] {
        RecordingSidebarGrouping.sections(for: filteredRecordings)
    }

    var selectedRecordingID: String? {
        get { recordings.first { sidebarSelection.contains($0.id) }?.id }
        set {
            if let newValue {
                selectRecording(newValue)
            } else {
                sidebarSelection.subtract(recordings.map(\.id))
            }
        }
    }

    var selectedInboxItems: [InboxItem] {
        inboxItems.filter { sidebarSelection.contains($0.id) }
    }

    var selectedRecordings: [RecordingRecord] {
        recordings.filter { sidebarSelection.contains($0.id) }
    }

    var selectedRecording: RecordingRecord? {
        guard let selectedRecordingID else { return nil }
        return recordings.first { $0.id == selectedRecordingID }
    }

    func selectRecording(_ id: String?) {
        if let id {
            sidebarSelection.subtract(inboxItems.map(\.id))
            sidebarSelection.insert(id)
        } else {
            sidebarSelection.subtract(recordings.map(\.id))
        }
    }

    var quitWarningMessage: String {
        var parts = ["Quitting will stop active jobs and discard in-progress work."]

        if let activeTranscriptionRecordingID,
           let recording = recordings.first(where: { $0.id == activeTranscriptionRecordingID }) {
            parts.append("Transcribing: “\(recording.title)”.")
        }
        if let activeSummaryRecordingID,
           let recording = recordings.first(where: { $0.id == activeSummaryRecordingID }) {
            parts.append("Summarizing: “\(recording.title)”.")
        }
        if let activePublishRecordingID,
           let recording = recordings.first(where: { $0.id == activePublishRecordingID }) {
            parts.append("Publishing: “\(recording.title)”.")
        }

        return parts.joined(separator: " ")
    }

    func loadLibrary() {
        recordings = store.allRecordings()
        refreshInbox()

        if selectedRecordingID == nil {
            selectRecording(recordings.first?.id)
        }
    }

    func refreshInbox() {
        inboxItems = library.inboxItems()
    }

    func addFilesToInbox(_ urls: [URL]) {
        receiveImportedFiles(urls, source: .filePicker)
    }

    func receiveDroppedFiles(_ urls: [URL]) {
        receiveImportedFiles(urls, source: .dragDrop)
    }

    private func receiveImportedFiles(_ urls: [URL], source: RecordingSource) {
        let audioFiles = AudioFileFilter.filter(urls)
        let transcriptionFiles = TranscriptionFileFilter.filter(urls)

        guard !audioFiles.isEmpty || !transcriptionFiles.isEmpty else {
            errorMessage = "No supported audio or transcription files were found."
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        if !audioFiles.isEmpty {
            if source == .dragDrop || source == .filePicker {
                library.addToInbox(audioFiles)
                refreshInbox()
            } else {
                receiveAudioFiles(audioFiles, source: source)
            }
        }

        if !transcriptionFiles.isEmpty {
            receiveTranscriptionFiles(transcriptionFiles, source: .transcriptImport)
        }
    }

    func receiveAudioFiles(_ urls: [URL], source: RecordingSource) {
        let audioFiles = AudioFileFilter.filter(urls)
        guard !audioFiles.isEmpty else {
            errorMessage = "No supported audio files were found."
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        do {
            let results = try library.importAudioFiles(audioFiles, source: source)
            for result in results {
                upsertRecording(result.record)
            }
            if let first = results.first {
                selectRecording(first.record.id)
            }
        } catch RecordingLibraryError.duplicateFound(let existing) {
            duplicateImportPrompt = DuplicateImportPrompt(
                existing: existing,
                pendingURLs: audioFiles,
                source: source,
                importKind: .audio
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func receiveTranscriptionFiles(_ urls: [URL], source: RecordingSource) {
        let transcriptionFiles = TranscriptionFileFilter.filter(urls)
        guard !transcriptionFiles.isEmpty else {
            errorMessage = "No supported transcription files were found."
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        do {
            let results = try library.importTranscriptionFiles(transcriptionFiles, source: source)
            for result in results {
                upsertRecording(result.record)
                enqueueTitleGeneration(for: result.record.id)
            }
            if let first = results.first {
                selectRecording(first.record.id)
            }
        } catch RecordingLibraryError.duplicateFound(let existing) {
            duplicateImportPrompt = DuplicateImportPrompt(
                existing: existing,
                pendingURLs: transcriptionFiles,
                source: source,
                importKind: .transcription
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmDuplicateImport(createAnyway: Bool) {
        guard let prompt = duplicateImportPrompt else { return }
        duplicateImportPrompt = nil

        guard createAnyway else {
            selectRecording(prompt.existing.id)
            return
        }

        do {
            switch prompt.importKind {
            case .audio:
                if prompt.source == .inbox, let url = prompt.pendingURLs.first {
                    let item = InboxItem(
                        id: url.standardizedFileURL.path,
                        url: url,
                        displayName: url.deletingPathExtension().lastPathComponent,
                        modifiedAt: Date(),
                        contentHash: try library.contentHash(for: url),
                        duration: AudioDuration.seconds(for: url)
                    )
                    let result = try library.importFromInbox(item, allowDuplicate: true)
                    upsertRecording(result.record)
                    selectRecording(result.record.id)
                    refreshInbox()
                } else {
                    let results = try library.importAudioFiles(
                        prompt.pendingURLs,
                        source: prompt.source,
                        allowDuplicate: true
                    )
                    for result in results {
                        upsertRecording(result.record)
                    }
                    selectRecording(results.first?.record.id)
                }
            case .transcription:
                let results = try library.importTranscriptionFiles(
                    prompt.pendingURLs,
                    source: prompt.source,
                    allowDuplicate: true
                )
                for result in results {
                    upsertRecording(result.record)
                    enqueueTitleGeneration(for: result.record.id)
                }
                selectRecording(results.first?.record.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importInboxItem(_ item: InboxItem) {
        importInboxItems([item])
    }

    func importInboxItems(_ items: [InboxItem]) {
        guard !items.isEmpty else { return }

        var lastImported: RecordingRecord?
        for item in items {
            do {
                let result = try library.importFromInbox(item)
                upsertRecording(result.record)
                lastImported = result.record
                sidebarSelection.remove(item.id)
            } catch RecordingLibraryError.duplicateFound(let existing) {
                duplicateImportPrompt = DuplicateImportPrompt(
                    existing: existing,
                    pendingURLs: [item.url],
                    source: .inbox,
                    importKind: .audio
                )
                break
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }

        refreshInbox()
        if let lastImported {
            selectRecording(lastImported.id)
        }
    }

    func trashInboxItem(_ item: InboxItem) {
        trashInboxItems([item])
    }

    func trashInboxItems(_ items: [InboxItem]) {
        guard !items.isEmpty else { return }

        for item in items {
            do {
                try library.trashInboxItem(item)
                sidebarSelection.remove(item.id)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }

        refreshInbox()
    }

    func beginTranscription(for recordingID: String) {
        beginBulkTranscription(for: [recordingID])
    }

    func beginBulkTranscription(for recordingIDs: [String]) {
        let eligible = recordingIDs.filter { id in
            guard let record = recordings.first(where: { $0.id == id }),
                  record.hasAudio,
                  audioURL(for: record) != nil else { return false }
            return record.transcriptionStatus != .inProgress && record.transcriptionStatus != .queued
        }
        guard !eligible.isEmpty else { return }

        if isTranscriptionActive {
            let options = transcriptionQueue.first?.options ?? AppSettings.shared.defaultTranscriptionOptions()
            for id in eligible {
                enqueueTranscription(recordingID: id, options: options)
            }
            return
        }

        let title: String
        if eligible.count == 1, let recording = recordings.first(where: { $0.id == eligible[0] }) {
            title = recording.transcriptionStatus == .completed
                ? "Re-transcribe “\(recording.title)”"
                : "Transcribe “\(recording.title)”"
        } else {
            title = "Transcribe \(eligible.count) recordings"
        }

        pendingTranscriptionRequest = .recordingIDs(eligible, title: title)
    }

    func enqueueTranscription(recordingID: String, options: TranscriptionOptions) {
        guard !transcriptionQueue.contains(where: { $0.recordingID == recordingID }),
              activeTranscriptionRecordingID != recordingID else { return }

        transcriptionQueue.append(QueuedTranscriptionItem(recordingID: recordingID, options: options))
        pendingTranscriptionCount = transcriptionQueue.count
        updateRecording(recordingID) { record in
            record.transcriptionStatus = .queued
            record.transcriptionError = nil
        }
        startTranscriptionProcessorIfNeeded()
    }

    func beginSummary(for recordingID: String, regenerate: Bool = false) {
        beginBulkSummary(for: [recordingID], regenerate: regenerate)
    }

    func beginBulkSummary(for recordingIDs: [String], regenerate: Bool = false) {
        let eligible = recordingIDs.filter { id in
            guard let record = recordings.first(where: { $0.id == id }) else { return false }
            guard record.transcriptionStatus == .completed else { return false }
            return !record.summaryVariants.contains {
                $0.status == .queued || $0.status == .generating || $0.status == .publishing
            }
        }
        guard !eligible.isEmpty else { return }

        if isSummaryActive, let options = summaryQueue.first?.options {
            for id in eligible {
                enqueueSummary(recordingID: id, options: options, regenerate: regenerate)
            }
            return
        }

        summaryRequest = SummaryRequest(recordingIDs: eligible, regenerate: regenerate)
    }

    func enqueueSummary(recordingID: String, options: SummarizerOptions, regenerate: Bool) {
        guard !summaryQueue.contains(where: { $0.recordingID == recordingID && $0.options == options }),
              activeSummaryRecordingID != recordingID else { return }

        summaryQueue.append(QueuedSummaryItem(recordingID: recordingID, options: options, regenerate: regenerate))
        pendingSummaryCount = summaryQueue.count

        updateRecording(recordingID) { record in
            var variant = record.variant(for: options) ?? SummaryVariantRecord.make(options: options)
            variant.status = .queued
            variant.errorMessage = nil
            record.upsertVariant(variant)
        }

        startSummaryProcessorIfNeeded()
    }

    func beginPublish(recordingID: String, variantID: String) {
        beginBulkPublish(items: [PublishRequestItem(recordingID: recordingID, variantID: variantID)])
    }

    func beginBulkPublish(items: [PublishRequestItem]) {
        let eligible = items.filter { item in
            guard let record = recordings.first(where: { $0.id == item.recordingID }),
                  let variant = record.summaryVariants.first(where: { $0.id == item.variantID }) else {
                return false
            }
            let isPublishable = [.ready, .stale, .published, .failed].contains(variant.status)
            let isPublishing = record.summaryVariants.contains { $0.status == .publishing }
            return isPublishable && !isPublishing
        }
        guard !eligible.isEmpty else { return }

        publishRequest = PublishRequest(items: eligible)
    }

    func enqueuePublish(recordingID: String, variantID: String) {
        guard !publishQueue.contains(where: { $0.recordingID == recordingID && $0.variantID == variantID }),
              activePublishRecordingID != recordingID else { return }

        publishQueue.append(QueuedPublishItem(recordingID: recordingID, variantID: variantID))
        pendingPublishCount = publishQueue.count
        updateVariant(recordingID: recordingID, variantID: variantID) { variant in
            variant.status = .publishing
            variant.errorMessage = nil
        }
        startPublishProcessorIfNeeded()
    }

    func reloadTranscript(for recordingID: String) {
        guard var record = recordings.first(where: { $0.id == recordingID }) else { return }
        guard let url = store.transcriptURL(for: record),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        let previousText = store.readTranscript(for: record)
        if previousText != text {
            record.markSummariesStale()
            persist(record)
        }
    }

    func openTranscriptExternally(for recordingID: String) {
        guard let record = recordings.first(where: { $0.id == recordingID }),
              let url = store.transcriptURL(for: record) else { return }
        NSWorkspace.shared.open(url)
    }

    func saveSummaryMarkdown(for recordingID: String, variantID: String, markdown: String) {
        guard var record = recordings.first(where: { $0.id == recordingID }),
              var variant = record.summaryVariants.first(where: { $0.id == variantID }) else { return }

        do {
            _ = try store.writeSummary(markdown, for: &record, variant: &variant)
            variant.status = .ready
            record.upsertVariant(variant)
            persist(record)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealRecording(_ recordingID: String) {
        AppSupportPaths.revealInFinder(store.recordingDirectory(for: recordingID))
    }

    func revealInbox() {
        AppSupportPaths.revealInFinder(library.inboxDirectory)
    }

    func revealInboxItemsInFinder(_ items: [InboxItem]) {
        let urls = items.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openPublishedURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func deleteRecording(_ recordingID: String) {
        guard let record = recordings.first(where: { $0.id == recordingID }),
              record.transcriptionStatus != .inProgress,
              record.transcriptionStatus != .queued,
              activeSummaryRecordingID != recordingID,
              activePublishRecordingID != recordingID,
              !record.summaryVariants.contains(where: {
                  $0.status == .queued || $0.status == .generating || $0.status == .publishing
              }) else { return }

        transcriptionQueue.removeAll { $0.recordingID == recordingID }
        summaryQueue.removeAll { $0.recordingID == recordingID }
        publishQueue.removeAll { $0.recordingID == recordingID }
        store.delete(id: recordingID)
        recordings.removeAll { $0.id == recordingID }

        if selectedRecordingID == recordingID {
            selectRecording(recordings.first?.id)
        }
        sidebarSelection.remove(recordingID)
    }

    func deleteRecordings(_ recordingIDs: [String]) {
        for id in recordingIDs {
            deleteRecording(id)
        }
    }

    func stopAllQueues() {
        stopTranscriptionQueue()
        stopSummaryQueue()
        stopPublishQueue()
    }

    func stopTranscriptionQueue() {
        guard isTranscriptionActive else { return }
        stopTranscriptionRequested = true
        transcriptionTask?.cancel()
        transcriber.cancel()
        transcriptionQueue.removeAll()
        pendingTranscriptionCount = 0
        activeTranscriptionRecordingID = nil
        transcriptionProgress = nil
        resetTranscriptionStatuses()
        appendWhisperLog("\n# transcription queue stopped\n")
    }

    func stopSummaryQueue() {
        guard isSummaryActive else { return }
        stopSummaryRequested = true
        summaryTask?.cancel()
        adapter.cancel()
        summaryQueue.removeAll()
        pendingSummaryCount = 0
        activeSummaryRecordingID = nil
        resetSummaryStatuses()
    }

    func stopPublishQueue() {
        guard isPublishActive else { return }
        stopPublishRequested = true
        publishTask?.cancel()
        adapter.cancel()
        publishQueue.removeAll()
        pendingPublishCount = 0
        activePublishRecordingID = nil
    }

    func appendWhisperLog(_ chunk: String) {
        whisperLogText += chunk
        if let progress = WhisperProgressParser.latestProgress(in: whisperLogText) {
            transcriptionProgress = progress
        }
    }

    func clearWhisperLog() {
        whisperLogText = ""
        transcriptionProgress = nil
    }

    func transcriptionProgressLabel(for recordingID: String) -> String {
        guard activeTranscriptionRecordingID == recordingID,
              let transcriptionProgress else {
            return "Transcribing…"
        }
        return "Transcribing… \(Int((transcriptionProgress * 100).rounded()))%"
    }

    func audioURL(for record: RecordingRecord) -> URL? {
        guard let url = store.audioURL(for: record) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func transcriptText(for record: RecordingRecord) -> String? {
        store.readTranscript(for: record)
    }

    func summaryText(for record: RecordingRecord, variant: SummaryVariantRecord) -> String? {
        store.readSummary(for: record, variant: variant)
    }

    private func activeTranscriptionOptions(for record: RecordingRecord) -> TranscriptionOptions? {
        if let item = transcriptionQueue.first(where: { $0.recordingID == record.id }) {
            return item.options
        }
        return record.transcriptionOptions(defaultModelPath: AppSettings.shared.defaultModelPath)
            ?? AppSettings.shared.defaultTranscriptionOptions()
    }

    private func upsertRecording(_ record: RecordingRecord) {
        if let index = recordings.firstIndex(where: { $0.id == record.id }) {
            recordings[index] = record
        } else {
            recordings.insert(record, at: 0)
        }
        recordings.sort {
            if $0.displayDate != $1.displayDate {
                return $0.displayDate > $1.displayDate
            }
            return $0.importedAt > $1.importedAt
        }
    }

    private func persist(_ record: RecordingRecord) {
        do {
            try store.save(record)
            upsertRecording(record)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateRecording(_ recordingID: String, mutate: (inout RecordingRecord) -> Void) {
        guard var record = recordings.first(where: { $0.id == recordingID }) else { return }
        mutate(&record)
        persist(record)
    }

    private func updateVariant(recordingID: String, variantID: String, mutate: (inout SummaryVariantRecord) -> Void) {
        guard var record = recordings.first(where: { $0.id == recordingID }),
              var variant = record.summaryVariants.first(where: { $0.id == variantID }) else { return }
        mutate(&variant)
        record.upsertVariant(variant)
        persist(record)
    }

    private func matchesSearch(_ record: RecordingRecord) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return record.title.localizedCaseInsensitiveContains(query)
    }

    private func matchesSource(_ record: RecordingRecord) -> Bool {
        switch filterSource {
        case .all:
            return true
        case .inbox:
            return record.source == .inbox
        case .dragDrop:
            return record.source == .dragDrop
        case .filePicker:
            return record.source == .filePicker
        case .transcriptImport:
            return record.source == .transcriptImport
        }
    }

    private func matchesStatus(_ record: RecordingRecord) -> Bool {
        switch filterStatus {
        case .all:
            return true
        case .imported:
            return record.transcriptionStatus != .completed
        case .transcribed:
            return record.transcriptionStatus == .completed
        case .summarized:
            return record.summaryVariants.contains { $0.status == .ready || $0.status == .published || $0.status == .stale }
        case .published:
            return record.summaryVariants.contains { $0.status == .published }
        }
    }

    private func startTranscriptionProcessorIfNeeded() {
        guard transcriptionTask == nil else { return }
        transcriptionTask = Task {
            await runTranscriptionProcessor()
            transcriptionTask = nil
            stopTranscriptionRequested = false
            activeTranscriptionRecordingID = nil
            pendingTranscriptionCount = 0
            transcriptionProgress = nil
        }
    }

    private func startSummaryProcessorIfNeeded() {
        guard summaryTask == nil else { return }
        summaryTask = Task {
            await runSummaryProcessor()
            summaryTask = nil
            stopSummaryRequested = false
            activeSummaryRecordingID = nil
            pendingSummaryCount = 0
        }
    }

    private func startPublishProcessorIfNeeded() {
        guard publishTask == nil else { return }
        publishTask = Task {
            await runPublishProcessor()
            publishTask = nil
            stopPublishRequested = false
            activePublishRecordingID = nil
            pendingPublishCount = 0
        }
    }

    private func enqueueTitleGeneration(for recordingID: String) {
        guard !titleQueue.contains(recordingID) else { return }
        titleQueue.append(recordingID)
        startTitleProcessorIfNeeded()
    }

    private func startTitleProcessorIfNeeded() {
        guard titleTask == nil else { return }
        titleTask = Task {
            await runTitleProcessor()
            titleTask = nil
        }
    }

    private func runTitleProcessor() async {
        while !titleQueue.isEmpty {
            if Task.isCancelled { break }

            let recordingID = titleQueue.removeFirst()

            guard let record = recordings.first(where: { $0.id == recordingID }),
                  record.transcriptionStatus == .completed,
                  let transcriptURL = store.transcriptURL(for: record) else { continue }

            do {
                let title = try await adapter.generateTitle(transcriptPath: transcriptURL)
                guard var updated = recordings.first(where: { $0.id == recordingID }),
                      updated.transcriptionStatus == .completed else { continue }

                updated.title = title
                updated.titleGeneratedAt = Date()
                persist(updated)
            } catch {
                // Keep the original filename title if generation fails.
                continue
            }
        }
    }

    private func runTranscriptionProcessor() async {
        while !transcriptionQueue.isEmpty {
            if Task.isCancelled || stopTranscriptionRequested { break }

            let item = transcriptionQueue.removeFirst()
            pendingTranscriptionCount = transcriptionQueue.count

            guard var record = recordings.first(where: { $0.id == item.recordingID }),
                  let audioURL = audioURL(for: record) else { continue }

            activeTranscriptionRecordingID = record.id
            record.transcriptionStatus = .inProgress
            record.transcriptionError = nil
            persist(record)
            clearWhisperLog()
            appendWhisperLog(
                "$ whisper-cli -l \(item.options.language) \"\(audioURL.lastPathComponent)\"\n\n"
            )

            do {
                let transcript = try await transcriber.transcribe(
                    audioURL: audioURL,
                    options: item.options,
                    onLog: { [weak self] chunk in
                        self?.appendWhisperLog(chunk)
                    }
                )

                if Task.isCancelled || stopTranscriptionRequested {
                    record.transcriptionStatus = .notStarted
                    persist(record)
                    break
                }

                _ = try store.writeTranscript(transcript.text, for: &record)
                record.transcriptionStatus = .completed
                record.transcriptionLanguage = item.options.language
                record.transcriptionModelPath = item.options.modelPath
                record.transcribedAt = Date()
                record.transcriptionError = nil
                record.markSummariesStale()
                persist(record)
                appendWhisperLog("\n# completed successfully\n\n")
                enqueueTitleGeneration(for: record.id)
                JobNotification.post(
                    title: "Transcription complete",
                    body: "“\(record.title)” is ready."
                )
            } catch {
                if Task.isCancelled || stopTranscriptionRequested {
                    record.transcriptionStatus = .notStarted
                    persist(record)
                    break
                }
                record.transcriptionStatus = .failed
                record.transcriptionError = error.localizedDescription
                persist(record)
                errorMessage = error.localizedDescription
                appendWhisperLog("\n# failed: \(error.localizedDescription)\n\n")
            }

            activeTranscriptionRecordingID = nil
            transcriptionProgress = nil
        }

        if Task.isCancelled || stopTranscriptionRequested {
            transcriptionQueue.removeAll()
            pendingTranscriptionCount = 0
            resetTranscriptionStatuses()
        }
    }

    private func runSummaryProcessor() async {
        while !summaryQueue.isEmpty {
            if Task.isCancelled || stopSummaryRequested { break }

            let item = summaryQueue.removeFirst()
            pendingSummaryCount = summaryQueue.count

            guard var record = recordings.first(where: { $0.id == item.recordingID }),
                  let transcriptURL = store.transcriptURL(for: record) else { continue }

            activeSummaryRecordingID = record.id
            var variant = record.variant(for: item.options) ?? SummaryVariantRecord.make(options: item.options)
            variant.status = .generating
            variant.errorMessage = nil
            record.upsertVariant(variant)
            persist(record)

            let summaryURL = store.summariesDirectory(for: record.id)
                .appendingPathComponent("\(variant.id).md")

            do {
                let result = try await adapter.generateSummary(
                    transcriptPath: transcriptURL,
                    summaryPath: summaryURL,
                    recordingTitle: record.generatedTitle,
                    options: item.options,
                    skipCache: item.regenerate
                )

                if Task.isCancelled || stopSummaryRequested { break }

                variant.status = .ready
                variant.title = result.title
                variant.generatedAt = Date()
                variant.markdownFileName = summaryURL.lastPathComponent
                variant.errorMessage = nil
                record.upsertVariant(variant)
                persist(record)
                JobNotification.post(
                    title: "Summary ready",
                    body: "“\(record.title)” is ready to publish."
                )
            } catch {
                if Task.isCancelled || stopSummaryRequested { break }
                variant.status = .failed
                variant.errorMessage = error.localizedDescription
                record.upsertVariant(variant)
                persist(record)
                errorMessage = error.localizedDescription
            }

            activeSummaryRecordingID = nil
        }

        if Task.isCancelled || stopSummaryRequested {
            summaryQueue.removeAll()
            pendingSummaryCount = 0
            resetSummaryStatuses()
        }
    }

    private func runPublishProcessor() async {
        while !publishQueue.isEmpty {
            if Task.isCancelled || stopPublishRequested { break }

            let item = publishQueue.removeFirst()
            pendingPublishCount = publishQueue.count

            guard var record = recordings.first(where: { $0.id == item.recordingID }),
                  let transcriptURL = store.transcriptURL(for: record),
                  var variant = record.summaryVariants.first(where: { $0.id == item.variantID }),
                  let summaryURL = store.summaryURL(for: record, variant: variant) else { continue }

            activePublishRecordingID = record.id

            do {
                let result = try await adapter.publish(
                    transcriptPath: transcriptURL,
                    summaryPath: summaryURL,
                    recordingTitle: record.generatedTitle,
                    options: variant.options
                )

                if Task.isCancelled || stopPublishRequested { break }

                let attempt = PublishAttempt(
                    success: true,
                    destinationURL: result.documentURL?.absoluteString
                )
                variant.publishAttempts.append(attempt)
                variant.status = .published
                variant.title = result.title ?? variant.title
                variant.errorMessage = nil
                record.upsertVariant(variant)
                persist(record)
                JobNotification.post(
                    title: "Published to Notion",
                    body: "“\(record.title)” was published."
                )
            } catch {
                if Task.isCancelled || stopPublishRequested { break }
                let attempt = PublishAttempt(success: false, errorMessage: error.localizedDescription)
                variant.publishAttempts.append(attempt)
                variant.status = .failed
                variant.errorMessage = error.localizedDescription
                record.upsertVariant(variant)
                persist(record)
                errorMessage = error.localizedDescription
            }

            activePublishRecordingID = nil
        }
    }

    private func resetTranscriptionStatuses() {
        for index in recordings.indices {
            switch recordings[index].transcriptionStatus {
            case .queued, .inProgress:
                recordings[index].transcriptionStatus = .notStarted
                try? store.save(recordings[index])
            default:
                break
            }
        }
    }

    private func resetSummaryStatuses() {
        for index in recordings.indices {
            var record = recordings[index]
            let hadActiveSummaryJob = record.summaryVariants.contains {
                $0.status == .queued || $0.status == .generating
            }
            guard hadActiveSummaryJob else { continue }

            record.summaryVariants = record.summaryVariants.compactMap { variant in
                guard variant.status == .queued || variant.status == .generating else {
                    return variant
                }
                if variant.markdownFileName != nil {
                    var updated = variant
                    updated.status = .stale
                    return updated
                }
                return nil
            }

            try? store.save(record)
            recordings[index] = record
        }
    }
}

import AppKit
