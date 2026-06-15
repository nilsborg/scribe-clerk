import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var jobs: [TranscriptionJob] = []
    @Published var selectedJobID: String?
    @Published var pendingRequest: TranscriptionRequest?
    @Published var errorMessage: String?

    private let transcriber = WhisperTranscriber()
    private let transcriptStore = TranscriptStore.shared
    private var isTranscribing = false

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

        if selectedJobID == nil {
            selectedJobID = jobs.first?.id
        }
    }

    func receiveAudioFiles(_ urls: [URL]) {
        let audioFiles = AudioFileFilter.filter(urls)
        guard !audioFiles.isEmpty else {
            errorMessage = "No supported audio files were found. Try M4A, MP3, WAV, FLAC, or OGG."
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        for url in audioFiles {
            let job = TranscriptionJob.make(from: url)
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                if case .completed = jobs[index].status {
                    continue
                }
                jobs[index] = job
            } else {
                jobs.insert(job, at: 0)
            }
        }

        jobs.sort { $0.receivedAt > $1.receivedAt }
        selectedJobID = TranscriptionJob.stableID(for: audioFiles[0])

        let title: String
        if audioFiles.count == 1 {
            title = "Transcribe “\(audioFiles[0].deletingPathExtension().lastPathComponent)”"
        } else {
            title = "Transcribe \(audioFiles.count) Recordings"
        }

        pendingRequest = .files(audioFiles, title: title)
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

    func transcribe(job: TranscriptionJob, options: TranscriptionOptions) async {
        guard !isTranscribing else { return }

        isTranscribing = true
        updateJobStatus(id: job.id, status: .inProgress)
        errorMessage = nil

        do {
            let record = try await transcriber.transcribe(audioURL: job.audioURL, options: options)
            let stored = record.withSource(
                url: job.audioURL,
                name: job.displayName
            )
            try transcriptStore.save(stored, for: job.id)
            updateJobStatus(id: job.id, status: .completed(stored))
        } catch {
            updateJobStatus(id: job.id, status: .failed(error.localizedDescription))
            errorMessage = error.localizedDescription
        }

        isTranscribing = false
    }

    func transcribeBatch(urls: [URL], options: TranscriptionOptions) async {
        for url in urls {
            let job = jobs.first(where: { $0.id == TranscriptionJob.stableID(for: url) })
                ?? TranscriptionJob.make(from: url)
            await transcribe(job: job, options: options)
        }
    }

    func revealInFinder(_ job: TranscriptionJob) {
        NSWorkspace.shared.activateFileViewerSelecting([job.audioURL])
    }

    private func updateJobStatus(id: String, status: TranscriptionStatus) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = status
    }
}

import AppKit
