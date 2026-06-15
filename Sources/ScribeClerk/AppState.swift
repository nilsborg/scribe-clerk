import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var jobs: [TranscriptionJob] = []
    @Published var selectedJobIDs: Set<String> = []
    @Published var detailJobID: String?
    @Published var pendingRequest: TranscriptionRequest?
    @Published var summarizerRequest: SummarizerRequest?
    @Published var summarizerSuccessMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var activeTranscriptionJobID: String?
    @Published private(set) var pendingQueueCount = 0
    @Published private(set) var activeSummarizerJobID: String?
    @Published private(set) var pendingSummarizerQueueCount = 0
    @Published var isWhisperLogPanelVisible = false
    @Published private(set) var whisperLogText = ""

    private let transcriber = WhisperTranscriber()
    private let summarizer = MeetingSummarizerService()
    private let transcriptStore = TranscriptStore.shared
    private var transcriptionQueue: [QueuedTranscription] = []
    private var summarizerQueue: [QueuedSummarization] = []
    private var queueProcessorTask: Task<Void, Never>?
    private var summarizerProcessorTask: Task<Void, Never>?
    private var activeQueueOptions: TranscriptionOptions?
    private var activeSummarizerOptions: SummarizerOptions?
    private var stopRequested = false
    private var summarizerStopRequested = false

    var isQueueActive: Bool {
        queueProcessorTask != nil
    }

    var isSummarizerQueueActive: Bool {
        summarizerProcessorTask != nil
    }

    var transcriptionQuitWarningMessage: String {
        var parts = [
            "Quitting will stop whisper-cli and discard progress on the current recording."
        ]

        if let activeTranscriptionJobID,
           let job = jobs.first(where: { $0.id == activeTranscriptionJobID }) {
            parts.append("Currently transcribing: “\(job.displayName)”.")
        }

        if pendingQueueCount > 0 {
            let label = pendingQueueCount == 1 ? "file" : "files"
            parts.append("\(pendingQueueCount) more \(label) waiting in the queue.")
        }

        return parts.joined(separator: " ")
    }

    var queueJobIDs: [String] {
        var ids: [String] = []
        if let activeTranscriptionJobID {
            ids.append(activeTranscriptionJobID)
        }
        ids.append(contentsOf: transcriptionQueue.map(\.jobID))
        return ids
    }

    var summarizerQueueJobIDs: [String] {
        var ids: [String] = []
        if let activeSummarizerJobID {
            ids.append(activeSummarizerJobID)
        }
        ids.append(contentsOf: summarizerQueue.map(\.jobID))
        return ids
    }

    var libraryJobs: [TranscriptionJob] {
        let queueIDs = Set(queueJobIDs)
        return jobs.filter { !queueIDs.contains($0.id) }
    }

    func queuePosition(for jobID: String) -> Int? {
        guard let index = queueJobIDs.firstIndex(of: jobID) else { return nil }
        return index + 1
    }

    func summarizerQueuePosition(for jobID: String) -> Int? {
        guard let index = summarizerQueueJobIDs.firstIndex(of: jobID) else { return nil }
        return index + 1
    }

    func summarizerState(for jobID: String) -> SummarizerJobState {
        guard let position = summarizerQueuePosition(for: jobID) else { return .none }
        if position == 1 {
            return .inProgress
        }
        return .queued(position: position)
    }

    func loadHistory() {
        let saved = transcriptStore.allRecords()
        var loaded: [TranscriptionJob] = []

        for (key, record) in saved {
            guard let url = record.sourceURL else { continue }
            loaded.append(
                TranscriptionJob(
                    id: key,
                    audioURL: url,
                    displayName: record.sourceName ?? url.deletingPathExtension().lastPathComponent,
                    receivedAt: record.createdAt,
                    status: .completed(record)
                )
            )
        }

        jobs = loaded.sorted { $0.receivedAt > $1.receivedAt }

        if selectedJobIDs.isEmpty, let first = jobs.first?.id {
            selectJob(first)
        }
    }

    func receiveAudioFiles(_ urls: [URL]) {
        let audioFiles = AudioFileFilter.filter(urls)
        guard !audioFiles.isEmpty else {
            errorMessage = "No supported audio files were found. Try M4A, MP3, WAV, FLAC, or OGG."
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        registerJobs(for: audioFiles)

        if isQueueActive, let options = activeQueueOptions {
            let enqueued = enqueueTranscriptions(urls: audioFiles, options: options)
            if enqueued > 0 {
                selectJob(TranscriptionJob.stableID(for: audioFiles[0]))
            }
            return
        }

        selectJob(TranscriptionJob.stableID(for: audioFiles[0]))
        pendingRequest = transcriptionRequest(for: audioFiles)
    }

    func status(for job: TranscriptionJob) -> TranscriptionStatus {
        jobs.first(where: { $0.id == job.id })?.status ?? job.status
    }

    func transcriptText(for job: TranscriptionJob) -> String? {
        if case .completed(let record) = status(for: job) {
            return record.text
        }
        return nil
    }

    func summarizeTargets(for job: TranscriptionJob) -> Set<String> {
        let candidateIDs: Set<String>
        if selectedJobIDs.contains(job.id), selectedJobIDs.count > 1 {
            candidateIDs = selectedJobIDs
        } else {
            candidateIDs = [job.id]
        }

        return Set(candidateIDs.filter { jobID in
            guard let item = jobs.first(where: { $0.id == jobID }) else { return false }
            if case .completed = status(for: item) { return true }
            return false
        })
    }

    func beginSummarize(jobIDs: Set<String>) {
        let items = jobIDs.compactMap { id -> SummarizerRequestItem? in
            guard let job = jobs.first(where: { $0.id == id }),
                  case .completed(let record) = status(for: job) else {
                return nil
            }
            return SummarizerRequestItem(job: job, record: record)
        }

        guard !items.isEmpty else { return }

        if isSummarizerQueueActive, let options = activeSummarizerOptions {
            enqueueSummarizations(items: items, options: options)
            return
        }

        summarizerRequest = SummarizerRequest(items: items)
    }

    @discardableResult
    func enqueueTranscriptions(urls: [URL], options: TranscriptionOptions) -> Int {
        registerJobs(for: urls)
        activeQueueOptions = options

        var added = 0
        for url in urls {
            let jobID = TranscriptionJob.stableID(for: url)
            guard let job = jobs.first(where: { $0.id == jobID }) else { continue }
            guard shouldEnqueue(status: job.status) else { continue }

            if transcriptionQueue.contains(where: { $0.jobID == jobID }) {
                continue
            }

            transcriptionQueue.append(QueuedTranscription(jobID: jobID, options: options))
            updateJobStatus(id: jobID, status: .queued)
            added += 1
        }

        pendingQueueCount = transcriptionQueue.count
        startQueueProcessorIfNeeded()
        return added
    }

    @discardableResult
    func enqueueSummarizations(items: [SummarizerRequestItem], options: SummarizerOptions) -> Int {
        activeSummarizerOptions = options

        var added = 0
        for item in items {
            let jobID = item.job.id
            if summarizerQueue.contains(where: { $0.jobID == jobID }) {
                continue
            }
            if activeSummarizerJobID == jobID {
                continue
            }

            summarizerQueue.append(QueuedSummarization(jobID: jobID, options: options))
            added += 1
        }

        pendingSummarizerQueueCount = summarizerQueue.count
        startSummarizerProcessorIfNeeded()
        return added
    }

    func revealInFinder(_ job: TranscriptionJob) {
        NSWorkspace.shared.activateFileViewerSelecting([job.audioURL])
    }

    func canDelete(_ job: TranscriptionJob) -> Bool {
        switch status(for: job) {
        case .inProgress:
            return false
        default:
            return true
        }
    }

    func deleteJob(_ job: TranscriptionJob) {
        guard canDelete(job) else { return }

        transcriptionQueue.removeAll { $0.jobID == job.id }
        pendingQueueCount = transcriptionQueue.count
        summarizerQueue.removeAll { $0.jobID == job.id }
        pendingSummarizerQueueCount = summarizerQueue.count

        transcriptStore.delete(for: job.id)

        let formerIndex = jobs.firstIndex(where: { $0.id == job.id })
        jobs.removeAll { $0.id == job.id }

        selectedJobIDs.remove(job.id)

        if detailJobID == job.id {
            if jobs.isEmpty {
                detailJobID = nil
            } else if let formerIndex {
                let nextIndex = min(formerIndex, jobs.count - 1)
                detailJobID = jobs[nextIndex].id
            } else {
                detailJobID = jobs.first?.id
            }
        }
    }

    func stopQueue() {
        guard isQueueActive else { return }

        stopRequested = true
        queueProcessorTask?.cancel()
        transcriber.cancel()
        transcriptionQueue.removeAll()
        pendingQueueCount = 0
        activeTranscriptionJobID = nil
        resetQueuedAndInProgressJobs()
        appendWhisperLog("\n# queue stopped\n")
    }

    func stopSummarizerQueue() {
        guard isSummarizerQueueActive else { return }

        summarizerStopRequested = true
        summarizerProcessorTask?.cancel()
        summarizer.cancel()
        summarizerQueue.removeAll()
        pendingSummarizerQueueCount = 0
        activeSummarizerJobID = nil
    }

    func selectJob(_ jobID: String) {
        selectedJobIDs = [jobID]
        detailJobID = jobID
    }

    func syncDetailJobID() {
        if let detailJobID, selectedJobIDs.contains(detailJobID) {
            return
        }
        detailJobID = jobs.first(where: { selectedJobIDs.contains($0.id) })?.id
    }

    func appendWhisperLog(_ chunk: String) {
        whisperLogText += chunk
    }

    func clearWhisperLog() {
        whisperLogText = ""
    }

    private func beginWhisperLog(for job: TranscriptionJob, options: TranscriptionOptions) {
        let settings = AppSettings.shared
        let modelName = URL(fileURLWithPath: options.modelPath).lastPathComponent
        whisperLogText = ""
        appendWhisperLog(
            "$ \(settings.whisperBinaryPath) -m \(options.modelPath) -l \(options.language) -otxt -np -nt \"\(job.audioURL.path)\"\n"
        )
        appendWhisperLog("# model: \(modelName) · file: \(job.displayName)\n\n")
    }

    private func registerJobs(for urls: [URL]) {
        for url in urls {
            let job = TranscriptionJob.make(from: url)
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                if case .completed = jobs[index].status {
                    continue
                }
                if case .queued = jobs[index].status {
                    continue
                }
                if case .inProgress = jobs[index].status {
                    continue
                }
                jobs[index] = job
            } else {
                jobs.insert(job, at: 0)
            }
        }

        jobs.sort { $0.receivedAt > $1.receivedAt }
    }

    private func transcriptionRequest(for urls: [URL]) -> TranscriptionRequest {
        let title: String
        if urls.count == 1 {
            title = "Transcribe “\(urls[0].deletingPathExtension().lastPathComponent)”"
        } else {
            title = "Transcribe \(urls.count) Recordings"
        }
        return .files(urls, title: title)
    }

    private func shouldEnqueue(status: TranscriptionStatus) -> Bool {
        switch status {
        case .inProgress, .queued:
            return false
        case .notStarted, .failed, .completed:
            return true
        }
    }

    private func startQueueProcessorIfNeeded() {
        guard queueProcessorTask == nil else { return }

        queueProcessorTask = Task {
            await runQueueProcessor()
            finishQueueProcessor()
        }
    }

    private func finishQueueProcessor() {
        queueProcessorTask = nil
        activeQueueOptions = nil
        activeTranscriptionJobID = nil
        pendingQueueCount = 0
        stopRequested = false
    }

    private func startSummarizerProcessorIfNeeded() {
        guard summarizerProcessorTask == nil else { return }

        summarizerProcessorTask = Task {
            await runSummarizerProcessor()
            finishSummarizerProcessor()
        }
    }

    private func finishSummarizerProcessor() {
        summarizerProcessorTask = nil
        activeSummarizerOptions = nil
        activeSummarizerJobID = nil
        pendingSummarizerQueueCount = 0
        summarizerStopRequested = false
    }

    private func runQueueProcessor() async {
        while !transcriptionQueue.isEmpty {
            if Task.isCancelled || stopRequested {
                break
            }

            let item = transcriptionQueue.removeFirst()
            pendingQueueCount = transcriptionQueue.count

            guard let job = jobs.first(where: { $0.id == item.jobID }) else { continue }

            activeTranscriptionJobID = job.id
            updateJobStatus(id: job.id, status: .inProgress)
            errorMessage = nil
            beginWhisperLog(for: job, options: item.options)

            do {
                let record = try await transcriber.transcribe(
                    audioURL: job.audioURL,
                    options: item.options,
                    onLog: { [weak self] chunk in
                        self?.appendWhisperLog(chunk)
                    }
                )

                if Task.isCancelled || stopRequested {
                    updateJobStatus(id: job.id, status: .notStarted)
                    appendWhisperLog("\n# stopped\n\n")
                    break
                }

                let stored = record.withSource(
                    url: job.audioURL,
                    name: job.displayName
                )
                try transcriptStore.save(stored, for: job.id)
                updateJobStatus(id: job.id, status: .completed(stored))
                appendWhisperLog("\n# completed successfully\n\n")
            } catch is CancellationError {
                updateJobStatus(id: job.id, status: .notStarted)
                appendWhisperLog("\n# cancelled\n\n")
                break
            } catch WhisperTranscriberError.cancelled {
                updateJobStatus(id: job.id, status: .notStarted)
                appendWhisperLog("\n# cancelled\n\n")
                break
            } catch {
                if Task.isCancelled || stopRequested {
                    updateJobStatus(id: job.id, status: .notStarted)
                    appendWhisperLog("\n# stopped\n\n")
                    break
                }
                updateJobStatus(id: job.id, status: .failed(error.localizedDescription))
                errorMessage = error.localizedDescription
                appendWhisperLog("\n# failed: \(error.localizedDescription)\n\n")
            }

            activeTranscriptionJobID = nil
        }

        if Task.isCancelled || stopRequested {
            transcriptionQueue.removeAll()
            pendingQueueCount = 0
            resetQueuedAndInProgressJobs()
        }
    }

    private func runSummarizerProcessor() async {
        let settings = AppSettings.shared
        let repoRoot = URL(fileURLWithPath: settings.summarizerRepoPath, isDirectory: true)

        while !summarizerQueue.isEmpty {
            if Task.isCancelled || summarizerStopRequested {
                break
            }

            let item = summarizerQueue.removeFirst()
            pendingSummarizerQueueCount = summarizerQueue.count

            guard let job = jobs.first(where: { $0.id == item.jobID }),
                  case .completed(let record) = status(for: job) else {
                continue
            }

            activeSummarizerJobID = job.id
            errorMessage = nil
            summarizerSuccessMessage = nil

            do {
                let exported = try summarizer.exportTranscript(
                    text: record.text,
                    createdAt: record.createdAt,
                    sourceName: record.sourceName ?? job.displayName,
                    repoRoot: repoRoot
                )

                if Task.isCancelled || summarizerStopRequested {
                    break
                }

                try await summarizer.runPipeline(
                    searchTerm: exported.searchTerm,
                    options: item.options,
                    repoRoot: repoRoot,
                    denoPath: settings.denoBinaryPath
                )

                if Task.isCancelled || summarizerStopRequested {
                    break
                }

                summarizerSuccessMessage =
                    "Summary created for “\(exported.fileURL.lastPathComponent)”."
            } catch {
                if Task.isCancelled || summarizerStopRequested {
                    break
                }
                errorMessage = error.localizedDescription
            }

            activeSummarizerJobID = nil
        }

        if Task.isCancelled || summarizerStopRequested {
            summarizerQueue.removeAll()
            pendingSummarizerQueueCount = 0
        }
    }

    private func resetQueuedAndInProgressJobs() {
        for index in jobs.indices {
            switch jobs[index].status {
            case .queued, .inProgress:
                jobs[index].status = .notStarted
            default:
                break
            }
        }
    }

    private func updateJobStatus(id: String, status: TranscriptionStatus) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = status
    }
}

import AppKit
