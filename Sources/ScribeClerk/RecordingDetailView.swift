import SwiftUI

struct RecordingDetailView: View {
    let recording: RecordingRecord
    @ObservedObject var appState: AppState
    @State private var selectedTab: DetailTab = .overview

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview
        case transcript
        case summaries
        case publishing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .transcript: return "Transcript"
            case .summaries: return "Summaries"
            case .publishing: return "Publishing"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            HStack {
                Spacer(minLength: 0)
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        }
        .onChange(of: recording.transcriptionStatus) { oldStatus, newStatus in
            if oldStatus == .inProgress && newStatus == .completed {
                selectedTab = .transcript
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.title2.bold())
                Text(recording.displayDate, format: .dateTime.day().month().year().hour().minute())
                    .foregroundStyle(.secondary)
                Text(recording.source.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Reveal Folder") {
                appState.revealRecording(recording.id)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            OverviewTab(recording: recording, appState: appState)
        case .transcript:
            TranscriptTab(recording: recording, appState: appState)
        case .summaries:
            SummariesTab(recording: recording, appState: appState)
        case .publishing:
            PublishingTab(recording: recording, appState: appState)
        }
    }
}

private struct OverviewTab: View {
    let recording: RecordingRecord
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledContent("Transcription") {
                Text(transcriptionLabel)
            }
            LabeledContent("Summaries") {
                Text("\(recording.summaryVariants.count)")
            }
            LabeledContent("Published") {
                Text("\(recording.summaryVariants.filter { $0.status == .published }.count)")
            }

            HStack {
                Button("Transcribe") {
                    appState.beginTranscription(for: recording.id)
                }
                .disabled(recording.transcriptionStatus == .inProgress || recording.transcriptionStatus == .queued)

                if recording.transcriptionStatus == .completed {
                    Button("Summarize") {
                        appState.beginSummary(for: recording.id)
                    }
                }

                Button("Delete", role: .destructive) {
                    appState.deleteRecording(recording.id)
                }
            }
        }
    }

    private var transcriptionLabel: String {
        switch recording.transcriptionStatus {
        case .notStarted: return "Not started"
        case .queued: return "Queued"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .failed: return recording.transcriptionError ?? "Failed"
        }
    }
}

private struct TranscriptTab: View {
    let recording: RecordingRecord
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Transcribe / Re-transcribe") {
                    appState.beginTranscription(for: recording.id)
                }
                .disabled(recording.transcriptionStatus == .inProgress || recording.transcriptionStatus == .queued)

                if recording.transcriptionStatus == .completed {
                    Button("Open Externally") {
                        appState.openTranscriptExternally(for: recording.id)
                    }
                    Button {
                        appState.reloadTranscript(for: recording.id)
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .help("Reload transcript from file")
                }
            }

            Group {
                if let error = recording.transcriptionError, recording.transcriptionStatus == .failed {
                    CenteredEmptyState {
                        ContentUnavailableView {
                            Label("Transcription failed", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        }
                    }
                } else if recording.transcriptionStatus == .inProgress || recording.transcriptionStatus == .queued {
                    CenteredEmptyState {
                        ContentUnavailableView {
                            Label("Transcription running", systemImage: "waveform")
                        } description: {
                            TranscriptionProgressView(
                                recordingID: recording.id,
                                appState: appState
                            )
                        }
                    }
                } else if let text = appState.transcriptText(for: recording) {
                    ScrollView {
                        Text(text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    CenteredEmptyState {
                        ContentUnavailableView {
                            Label("No transcript yet", systemImage: "text.bubble")
                        } description: {
                            Text("Transcribe this recording to generate a transcript file.")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SummariesTab: View {
    let recording: RecordingRecord
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("New Summary") {
                    appState.beginSummary(for: recording.id)
                }
                .disabled(recording.transcriptionStatus != .completed)
            }

            Group {
                if recording.summaryVariants.isEmpty {
                    CenteredEmptyState {
                        ContentUnavailableView {
                            Label("No summaries", systemImage: "text.append")
                        } description: {
                            Text("Generate a summary after transcription completes.")
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(recording.summaryVariants) { variant in
                                SummaryVariantCard(
                                    recording: recording,
                                    variant: variant,
                                    appState: appState
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SummaryVariantCard: View {
    let recording: RecordingRecord
    let variant: SummaryVariantRecord
    @ObservedObject var appState: AppState
    @State private var draftMarkdown: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(variant.flow.label) · \(variant.language.label)")
                    .font(.headline)
                Spacer()
                Text(variant.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let title = variant.title {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let error = variant.errorMessage, variant.status == .failed {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let markdown = appState.summaryText(for: recording, variant: variant) {
                TextEditor(text: Binding(
                    get: { draftMarkdown.isEmpty ? markdown : draftMarkdown },
                    set: { draftMarkdown = $0 }
                ))
                .font(.body.monospaced())
                .frame(minHeight: 180)
                .onAppear { draftMarkdown = markdown }
                .onDisappear {
                    if !draftMarkdown.isEmpty, draftMarkdown != markdown {
                        appState.saveSummaryMarkdown(
                            for: recording.id,
                            variantID: variant.id,
                            markdown: draftMarkdown
                        )
                    }
                }
            }

            HStack {
                Button("Re-summarize") {
                    appState.beginSummary(for: recording.id, regenerate: true)
                }
                .disabled(variant.status == .generating)

                Button("Send to Notion") {
                    appState.beginPublish(recordingID: recording.id, variantID: variant.id)
                }
                .disabled(variant.status != .ready && variant.status != .stale && variant.status != .published && variant.status != .failed)

                if variant.status == .failed {
                    Button("Retry Publish") {
                        appState.beginPublish(recordingID: recording.id, variantID: variant.id)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PublishingTab: View {
    let recording: RecordingRecord
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if recording.summaryVariants.allSatisfy({ $0.publishAttempts.isEmpty }) {
                CenteredEmptyState {
                    ContentUnavailableView {
                        Label("No publish history", systemImage: "paperplane")
                    } description: {
                        Text("Publish a summary from the Summaries tab.")
                    }
                }
            } else {
                List {
                    ForEach(recording.summaryVariants) { variant in
                        if !variant.publishAttempts.isEmpty {
                            Section("\(variant.flow.label) · \(variant.language.label)") {
                                ForEach(variant.publishAttempts) { attempt in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Image(systemName: attempt.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                .foregroundStyle(attempt.success ? .green : .red)
                                            Text(attempt.attemptedAt, format: .dateTime.day().month().hour().minute())
                                        }
                                        if let url = attempt.destinationURL {
                                            Button(url) {
                                                appState.openPublishedURL(url)
                                            }
                                            .font(.caption)
                                        }
                                        if let error = attempt.errorMessage {
                                            Text(error)
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CenteredEmptyState<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                content()
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TranscriptionProgressView: View {
    let recordingID: String
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 10) {
            if appState.activeTranscriptionRecordingID == recordingID,
               let progress = appState.transcriptionProgress {
                ProgressView(value: progress) {
                    Text(appState.transcriptionProgressLabel(for: recordingID))
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)
            } else {
                ProgressView()
                Text(appState.activeTranscriptionRecordingID == recordingID
                    ? appState.transcriptionProgressLabel(for: recordingID)
                    : "Waiting in queue…")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
