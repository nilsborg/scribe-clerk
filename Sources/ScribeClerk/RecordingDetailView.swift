import AppKit
import SwiftUI

struct RecordingDetailView: View {
    let recording: RecordingRecord
    @ObservedObject var appState: AppState
    @State private var selectedTab: DetailTab = .transcript

    enum DetailTab: String, CaseIterable, Identifiable {
        case transcript
        case summaries

        var id: String { rawValue }

        var title: String {
            switch self {
            case .transcript: return "Transcript"
            case .summaries: return "Summaries"
            }
        }
    }

    private var isTranscribing: Bool {
        recording.transcriptionStatus == .inProgress || recording.transcriptionStatus == .queued
    }

    private var audioURL: URL? {
        appState.audioURL(for: recording)
    }

    private var workflow: RecordingWorkflow {
        RecordingWorkflow(recording: recording)
    }

    private var isSummarizing: Bool {
        recording.summaryVariants.contains { $0.status == .queued || $0.status == .generating }
    }

    private var isSummaryJobActive: Bool {
        recording.summaryVariants.contains {
            $0.status == .queued || $0.status == .generating
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
                .frame(maxWidth: 320)
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
        .onChange(of: isSummaryJobActive) { wasActive, isActive in
            if isActive && !wasActive {
                selectedTab = .summaries
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(recording.title)
                    .font(.title2.bold())

                HStack(spacing: 6) {
                    Text(recording.displayDate, format: .dateTime.day().month().year().hour().minute())
                    Text("·")
                    Text(recording.source.label)
                    if let audioURL, let duration = recording.resolvedAudioDuration(from: audioURL) {
                        Text("·")
                        Text(duration)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                StatusBadge(recording: recording, appState: appState)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            actionBar
        }
        .padding(24)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            primaryActionButton

            Menu {
                if recording.transcriptionStatus == .completed, recording.hasAudio {
                    Button {
                        appState.beginTranscription(for: recording.id)
                    } label: {
                        Label("Re-transcribe", systemImage: "waveform")
                    }
                    .disabled(isTranscribing)

                    if !recording.summaryVariants.isEmpty {
                        Button {
                            appState.beginSummary(for: recording.id, regenerate: true)
                        } label: {
                            Label("Re-summarize", systemImage: "text.append")
                        }
                        .disabled(isSummarizing)
                    }

                    Button {
                        appState.openTranscriptExternally(for: recording.id)
                    } label: {
                        Label("Open Transcript Externally", systemImage: "arrow.up.forward.app")
                    }
                    Button {
                        appState.reloadTranscript(for: recording.id)
                    } label: {
                        Label("Reload Transcript", systemImage: "arrow.clockwise")
                    }

                    Divider()
                }

                Button {
                    appState.revealRecording(recording.id)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Divider()
                Button(role: .destructive) {
                    appState.deleteRecording(recording.id)
                } label: {
                    Label("Delete Recording", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch workflow.step {
        case .needsTranscription:
            Button {
                appState.beginTranscription(for: recording.id)
            } label: {
                Label(workflow.primaryActionTitle, systemImage: "waveform")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTranscribing)

        case .needsSummary:
            Button {
                appState.beginSummary(for: recording.id)
            } label: {
                Label(workflow.primaryActionTitle, systemImage: "text.append")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSummarizing)

        case .summarized:
            Button {
                appState.beginSummary(for: recording.id, regenerate: true)
            } label: {
                Label(workflow.primaryActionTitle, systemImage: "text.append")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSummarizing)

        case .inProgress:
            Button {} label: {
                Label(workflow.primaryActionTitle, systemImage: workflow.primaryActionIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .transcript:
            TranscriptTab(recording: recording, appState: appState)
        case .summaries:
            SummariesTab(recording: recording, appState: appState)
        }
    }
}

private struct TranscriptTab: View {
    let recording: RecordingRecord
    @ObservedObject var appState: AppState

    var body: some View {
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
                        Label(
                            recording.transcriptionStatus == .queued ? "Transcription queued" : "Transcription running",
                            systemImage: "waveform"
                        )
                    } description: {
                        JobProgressView(
                            kind: .transcription,
                            recordingID: recording.id,
                            appState: appState,
                            isQueued: recording.transcriptionStatus == .queued
                        )
                    }
                }
            } else if let text = appState.transcriptText(for: recording) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        CopyTranscriptButton(text: text)
                    }
                    ScrollView {
                        Text(text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                CenteredEmptyState {
                    ContentUnavailableView {
                        Label("No transcript yet", systemImage: "text.bubble")
                    } description: {
                        Text("Transcribe this recording to generate a transcript.")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CopyTranscriptButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy Transcript",
                  systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .disabled(copied)
    }
}

private struct SummariesTab: View {
    let recording: RecordingRecord
    @ObservedObject var appState: AppState

    private var summaryJobPhase: SummaryJobPhase? {
        if recording.summaryVariants.contains(where: { $0.status == .generating }) {
            return .running
        }
        if recording.summaryVariants.contains(where: { $0.status == .queued }) {
            return .queued
        }
        return nil
    }

    private var displayableVariants: [SummaryVariantRecord] {
        recording.summaryVariants.filter {
            $0.status != .queued && $0.status != .generating
        }
    }

    var body: some View {
        Group {
            if let phase = summaryJobPhase {
                CenteredEmptyState {
                    ContentUnavailableView {
                        Label(phase.title, systemImage: phase.icon)
                    } description: {
                        JobProgressView(
                            kind: .summary,
                            recordingID: recording.id,
                            appState: appState,
                            isQueued: phase == .queued
                        )
                    }
                }
            } else if displayableVariants.isEmpty {
                CenteredEmptyState {
                    ContentUnavailableView {
                        Label("No summaries", systemImage: "text.append")
                    } description: {
                        Text(recording.transcriptionStatus == .completed
                            ? "Use Summarize to generate a summary from the transcript."
                            : "Transcribe this recording first, then generate a summary.")
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(displayableVariants) { variant in
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum SummaryJobPhase {
    case queued
    case running

    var title: String {
        switch self {
        case .queued: return "Summary queued"
        case .running: return "Summary running"
        }
    }

    var icon: String {
        switch self {
        case .queued: return "clock"
        case .running: return "text.append"
        }
    }
}

private struct SummaryVariantCard: View {
    let recording: RecordingRecord
    let variant: SummaryVariantRecord
    @ObservedObject var appState: AppState
    @State private var draftMarkdown: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(variant.flow.label) · \(variant.language.label)")
                    .font(.headline)
                Spacer()
                VariantStatusBadge(status: variant.status)
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
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
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

        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct RecordingWorkflow {
    enum Step {
        case needsTranscription
        case needsSummary
        case summarized
        case inProgress
    }

    let recording: RecordingRecord
    let step: Step
    let primaryActionTitle: String
    let primaryActionIcon: String

    init(recording: RecordingRecord) {
        self.recording = recording

        if recording.transcriptionStatus == .inProgress || recording.transcriptionStatus == .queued {
            step = .inProgress
            primaryActionTitle = recording.transcriptionStatus == .queued ? "Queued…" : "Transcribing…"
            primaryActionIcon = "waveform"
            return
        }

        if !recording.hasAudio,
           recording.transcriptionStatus == .completed,
           Self.needsFirstSummary(recording) {
            step = .needsSummary
            primaryActionTitle = "Summarize"
            primaryActionIcon = "text.append"
            return
        }

        if recording.transcriptionStatus != .completed {
            step = .needsTranscription
            primaryActionTitle = recording.transcriptionStatus == .failed ? "Retry Transcribe" : "Transcribe"
            primaryActionIcon = "waveform"
            return
        }

        if recording.summaryVariants.contains(where: { $0.status == .queued }) {
            step = .inProgress
            primaryActionTitle = "Queued…"
            primaryActionIcon = "clock"
            return
        }

        if recording.summaryVariants.contains(where: { $0.status == .generating }) {
            step = .inProgress
            primaryActionTitle = "Summarizing…"
            primaryActionIcon = "text.append"
            return
        }

        if Self.needsFirstSummary(recording) {
            step = .needsSummary
            primaryActionTitle = "Summarize"
            primaryActionIcon = "text.append"
            return
        }

        step = .summarized
        primaryActionTitle = "Re-summarize"
        primaryActionIcon = "text.append"
    }

    private static func needsFirstSummary(_ recording: RecordingRecord) -> Bool {
        recording.summaryVariants.isEmpty
            || recording.summaryVariants.allSatisfy {
                $0.status == .notStarted || ($0.status == .failed && $0.markdownFileName == nil)
            }
    }
}

private struct VariantStatusBadge: View {
    let status: SummaryVariantStatus

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var label: String {
        switch status {
        case .notStarted: return "Not started"
        case .queued: return "Queued"
        case .generating: return "Generating"
        case .ready: return "Ready"
        case .failed: return "Failed"
        case .stale: return "Stale"
        }
    }

    private var color: Color {
        switch status {
        case .ready: return .blue
        case .failed: return .red
        case .queued: return .accentColor
        case .generating: return .accentColor
        case .stale: return .orange
        case .notStarted: return .secondary
        }
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

private struct JobProgressView: View {
    enum Kind {
        case transcription
        case summary
    }

    let kind: Kind
    let recordingID: String
    @ObservedObject var appState: AppState
    let isQueued: Bool

    var body: some View {
        VStack(spacing: 10) {
            if kind == .transcription,
               !isQueued,
               appState.activeTranscriptionRecordingID == recordingID,
               let progress = appState.transcriptionProgress {
                ProgressView(value: progress) {
                    Text(appState.transcriptionProgressLabel(for: recordingID))
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)
            } else {
                ProgressView()
                Text(statusText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        if isQueued {
            return "Waiting in queue…"
        }

        switch kind {
        case .transcription:
            return appState.transcriptionProgressLabel(for: recordingID)
        case .summary:
            return "Summarizing…"
        }
    }
}
