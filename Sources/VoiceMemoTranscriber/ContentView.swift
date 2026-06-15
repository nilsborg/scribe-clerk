import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var showFileImporter = false

    private var selectedJob: TranscriptionJob? {
        guard let selectedJobID = appState.selectedJobID else { return nil }
        return appState.jobs.first { $0.id == selectedJobID }
    }

    var body: some View {
        Group {
            if let job = selectedJob {
                JobDetailView(
                    job: job,
                    status: appState.status(for: job),
                    isSummarizing: appState.isSummarizing,
                    onTranscribe: {
                        appState.pendingRequest = .files(
                            [job.audioURL],
                            title: "Transcribe “\(job.displayName)”"
                        )
                    },
                    onReveal: {
                        appState.revealInFinder(job)
                    },
                    onSummarize: { record in
                        appState.summarizerRequest = SummarizerRequest(job: job, record: record)
                    }
                )
            } else {
                emptyState
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .onDrop(of: AudioDropTypes.accepted, isTargeted: nil, perform: handleWindowDrop)
        .toolbar {
            if appState.jobs.count > 1 {
                ToolbarItem(placement: .navigation) {
                    Picker("Transcript", selection: $appState.selectedJobID) {
                        ForEach(appState.jobs) { job in
                            Text(job.displayName).tag(job.id as String?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Open Audio", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: AudioFileFilter.acceptedTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                appState.receiveAudioFiles(urls)
            }
        }
        .sheet(item: $appState.pendingRequest) { request in
            TranscriptionOptionsView(
                request: request,
                onCancel: { appState.pendingRequest = nil },
                onStart: { options in
                    let urls = request.urls
                    appState.pendingRequest = nil
                    Task {
                        if urls.count == 1,
                           let job = appState.jobs.first(where: { $0.id == TranscriptionJob.stableID(for: urls[0]) }) {
                            await appState.transcribe(job: job, options: options)
                        } else {
                            await appState.transcribeBatch(urls: urls, options: options)
                        }
                    }
                }
            )
        }
        .sheet(item: $appState.summarizerRequest) { request in
            SummarizerOptionsView(
                request: request,
                onCancel: { appState.summarizerRequest = nil },
                onStart: { options in
                    let job = request.job
                    let record = request.record
                    appState.summarizerRequest = nil
                    Task {
                        await appState.sendToSummarizer(job: job, record: record, options: options)
                    }
                }
            )
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .alert("Summary sent", isPresented: summarizerSuccessBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.summarizerSuccessMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            AudioDropZone(
                title: "Drop recordings here",
                subtitle: "Drag from Voice Memos, Finder, or any audio file"
            ) { urls in
                appState.receiveAudioFiles(urls)
            }

            VStack(spacing: 8) {
                Text("From Voice Memos")
                    .font(.subheadline.weight(.semibold))

                Text("Drag a recording from the Voice Memos list and drop it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Open Voice Memos") {
                    NSWorkspace.shared.openApplication(
                        at: URL(fileURLWithPath: "/System/Applications/VoiceMemos.app"),
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                }
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 8)
        }
    }

    private func handleWindowDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            let urls = await DroppedFileLoader.loadURLs(from: providers)
            guard !urls.isEmpty else { return }
            await MainActor.run {
                appState.receiveAudioFiles(urls)
            }
        }
        return true
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appState.errorMessage = nil
                }
            }
        )
    }

    private var summarizerSuccessBinding: Binding<Bool> {
        Binding(
            get: { appState.summarizerSuccessMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appState.summarizerSuccessMessage = nil
                }
            }
        )
    }
}

private struct JobDetailView: View {
    let job: TranscriptionJob
    let status: TranscriptionStatus
    let isSummarizing: Bool
    let onTranscribe: () -> Void
    let onReveal: () -> Void
    let onSummarize: (TranscriptRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.displayName)
                        .font(.title2.bold())

                    Text(job.formattedDate)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reveal in Finder", action: onReveal)

                Button(action: onTranscribe) {
                    if case .inProgress = status {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(statusButtonTitle, systemImage: "waveform")
                    }
                }
                .disabled(isTranscribeDisabled)
            }

            Divider()

            transcriptContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var transcriptContent: some View {
        switch status {
        case .notStarted:
            ContentUnavailableView(
                "Ready to transcribe",
                systemImage: "text.bubble",
                description: Text("Choose language and model, then run Whisper on this recording.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .inProgress:
            VStack(spacing: 12) {
                ProgressView()
                Text("Running whisper-cli…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .completed(let record):
            VStack(alignment: .leading, spacing: 12) {
                TranscriptionMetadataBanner(record: record)

                ScrollView {
                    Text(record.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button {
                        onSummarize(record)
                    } label: {
                        if isSummarizing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Summarize", systemImage: "text.append")
                        }
                    }
                    .disabled(isSummarizing)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.text, forType: .string)
                    } label: {
                        Label("Copy transcript", systemImage: "doc.on.doc")
                    }
                    .disabled(isSummarizing)

                    ShareLink(item: record.text) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isSummarizing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .failed(let message):
            ContentUnavailableView {
                Label("Transcription failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusButtonTitle: String {
        switch status {
        case .completed:
            return "Re-transcribe"
        case .failed:
            return "Retry"
        default:
            return "Transcribe"
        }
    }

    private var isTranscribeDisabled: Bool {
        if case .inProgress = status {
            return true
        }
        return false
    }
}

private struct TranscriptionMetadataBanner: View {
    let record: TranscriptRecord

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.and.mic")
                .foregroundStyle(.secondary)

            Text(record.optionsSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(record.createdAt, format: .dateTime.day().month().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

import AppKit
