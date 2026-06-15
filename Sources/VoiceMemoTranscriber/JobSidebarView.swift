import SwiftUI

struct JobSidebarView: View {
    @ObservedObject var appState: AppState
    let onAddFiles: () -> Void

    var body: some View {
        List(selection: $appState.selectedJobIDs) {
            if appState.isQueueActive {
                Section {
                    QueueControls(
                        title: "Transcribing",
                        activeJobName: appState.activeTranscriptionJobID.flatMap { id in
                            appState.jobs.first(where: { $0.id == id })?.displayName
                        },
                        pendingCount: appState.pendingQueueCount,
                        onStop: appState.stopQueue
                    )
                }

                Section("Transcription Queue") {
                    ForEach(appState.queueJobIDs, id: \.self) { jobID in
                        sidebarRow(for: jobID, queuePosition: appState.queuePosition(for: jobID))
                    }
                }
            }

            if appState.isSummarizerQueueActive {
                Section {
                    QueueControls(
                        title: "Summarizing",
                        activeJobName: appState.activeSummarizerJobID.flatMap { id in
                            appState.jobs.first(where: { $0.id == id })?.displayName
                        },
                        pendingCount: appState.pendingSummarizerQueueCount,
                        onStop: appState.stopSummarizerQueue
                    )
                }

                Section("Summarizer Queue") {
                    ForEach(appState.summarizerQueueJobIDs, id: \.self) { jobID in
                        sidebarRow(
                            for: jobID,
                            queuePosition: appState.summarizerQueuePosition(for: jobID),
                            summarizerState: appState.summarizerState(for: jobID)
                        )
                    }
                }
            }

            Section(historySectionTitle) {
                if appState.jobs.isEmpty {
                    ContentUnavailableView {
                        Label("No recordings", systemImage: "waveform")
                    } description: {
                        Text("Drop audio files or use + to add recordings.")
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(historyJobs) { job in
                        sidebarRow(
                            for: job.id,
                            queuePosition: nil,
                            summarizerState: appState.summarizerState(for: job.id)
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Recordings")
        .onChange(of: appState.selectedJobIDs) { _, _ in
            appState.syncDetailJobID()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onAddFiles) {
                    Label("Open Audio", systemImage: "plus")
                }
            }
        }
    }

    private var historySectionTitle: String {
        if appState.isQueueActive || appState.isSummarizerQueueActive {
            return "History"
        }
        return "Recordings"
    }

    private var historyJobs: [TranscriptionJob] {
        let busyIDs = Set(appState.queueJobIDs + appState.summarizerQueueJobIDs)
        if appState.isQueueActive || appState.isSummarizerQueueActive {
            return appState.jobs.filter { !busyIDs.contains($0.id) }
        }
        return appState.jobs
    }

    @ViewBuilder
    private func sidebarRow(
        for jobID: String,
        queuePosition: Int?,
        summarizerState: SummarizerJobState = .none
    ) -> some View {
        if let job = appState.jobs.first(where: { $0.id == jobID }) {
            JobSidebarRow(
                job: job,
                status: appState.status(for: job),
                queuePosition: queuePosition,
                summarizerState: summarizerState,
                summarizeTargetCount: appState.summarizeTargets(for: job).count,
                canDelete: appState.canDelete(job),
                onSummarize: { appState.beginSummarize(jobIDs: appState.summarizeTargets(for: job)) },
                onDelete: { appState.deleteJob(job) }
            )
            .tag(job.id)
        }
    }
}

private struct QueueControls: View {
    let title: String
    let activeJobName: String?
    let pendingCount: Int
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let activeJobName {
                        Text(activeJobName)
                            .lineLimit(1)
                            .font(.callout.weight(.medium))
                    } else {
                        Text("Processing…")
                            .font(.callout.weight(.medium))
                    }

                    if pendingCount > 0 {
                        Text("\(pendingCount) waiting")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            Button("Stop", role: .destructive, action: onStop)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

private struct JobSidebarRow: View {
    let job: TranscriptionJob
    let status: TranscriptionStatus
    let queuePosition: Int?
    let summarizerState: SummarizerJobState
    let summarizeTargetCount: Int
    let canDelete: Bool
    let onSummarize: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: leadingIcon)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let queuePosition, queuePosition > 1 {
                Text("#\(queuePosition)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if summarizeTargetCount > 0 {
                Button {
                    onSummarize()
                } label: {
                    if summarizeTargetCount > 1 {
                        Label("Summarize \(summarizeTargetCount) Transcripts", systemImage: "text.append")
                    } else {
                        Label("Summarize", systemImage: "text.append")
                    }
                }
            }

            Button("Delete", role: .destructive, action: onDelete)
                .disabled(!canDelete)
        }
    }

    private var leadingIcon: String {
        switch summarizerState {
        case .inProgress:
            return "text.append"
        case .queued:
            return "clock.badge.text"
        default:
            return status.statusIcon
        }
    }

    private var subtitle: String {
        switch summarizerState {
        case .inProgress:
            return "Summarizing…"
        case .queued(let position):
            return "Summary queue #\(position)"
        default:
            break
        }

        if let queuePosition {
            if queuePosition == 1 {
                return "Transcribing now"
            }
            return "Transcription queue #\(queuePosition)"
        }

        switch status {
        case .completed:
            return job.formattedDate
        default:
            return status.statusLabel
        }
    }

    private var iconColor: Color {
        switch summarizerState {
        case .inProgress:
            return .accentColor
        case .queued:
            return .purple
        case .none:
            break
        }

        switch status {
        case .inProgress:
            return .accentColor
        case .queued:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        case .notStarted:
            return .secondary
        }
    }
}
