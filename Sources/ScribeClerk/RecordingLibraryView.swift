import SwiftUI

struct RecordingLibraryView: View {
    @ObservedObject var appState: AppState
    let onAddFiles: () -> Void

    var body: some View {
        List(selection: $appState.sidebarSelection) {
            if appState.isTranscriptionActive || appState.isSummaryActive || appState.isPublishActive {
                Section {
                    ActiveJobsBanner(appState: appState)
                }
            }

            if !appState.inboxItems.isEmpty {
                Section("Inbox") {
                    ForEach(appState.inboxItems) { item in
                        InboxRow(
                            item: item,
                            appState: appState,
                            onImport: { appState.importInboxItem(item) },
                            onTrash: { appState.trashInboxItem(item) }
                        )
                        .tag(item.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                appState.trashInboxItem(item)
                            } label: {
                                Label("Trash", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        let items = indexSet.map { appState.inboxItems[$0] }
                        appState.trashInboxItems(items)
                    }
                }
            }

            Section("Library") {
                if appState.filteredRecordings.isEmpty {
                    ContentUnavailableView {
                        Label("No recordings", systemImage: "waveform")
                    } description: {
                        Text("Import files from the inbox to start transcribing.")
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(appState.filteredRecordings) { recording in
                        RecordingSidebarRow(recording: recording)
                            .tag(recording.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Recordings")
        .searchable(text: $appState.searchText, prompt: "Search recordings")
        .toolbar {
            if !appState.selectedInboxItems.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.importInboxItems(appState.selectedInboxItems)
                    } label: {
                        Label(
                            "Import \(appState.selectedInboxItems.count)",
                            systemImage: "tray.and.arrow.down"
                        )
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        appState.trashInboxItems(appState.selectedInboxItems)
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: onAddFiles) {
                    Label("Add to Inbox", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker("Source", selection: $appState.filterSource) {
                        ForEach(RecordingFilterSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }

                    Picker("Status", selection: $appState.filterStatus) {
                        ForEach(RecordingFilterStatus.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}

private struct ActiveJobsBanner: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.isTranscriptionActive {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(appState.transcriptionProgressLabel(for: appState.activeTranscriptionRecordingID ?? ""))
                        Spacer()
                        Button("Stop", role: .destructive) {
                            appState.stopTranscriptionQueue()
                        }
                        .controlSize(.small)
                    }

                    if let progress = appState.transcriptionProgress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            if appState.isSummaryActive {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Summarizing…")
                    Spacer()
                    Button("Stop", role: .destructive) {
                        appState.stopSummaryQueue()
                    }
                    .controlSize(.small)
                }
            }
            if appState.isPublishActive {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Publishing…")
                    Spacer()
                    Button("Stop", role: .destructive) {
                        appState.stopPublishQueue()
                    }
                    .controlSize(.small)
                }
            }
        }
        .font(.caption)
    }
}

private struct InboxRow: View {
    let item: InboxItem
    @ObservedObject var appState: AppState
    let onImport: () -> Void
    let onTrash: () -> Void

    private var bulkSelection: [InboxItem] {
        let selected = appState.selectedInboxItems
        return selected.contains(item) && selected.count > 1 ? selected : []
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Import", action: onImport)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
        .contextMenu {
            if bulkSelection.isEmpty {
                Button("Import", action: onImport)
                Divider()
                Button("Move to Trash", role: .destructive, action: onTrash)
            } else {
                Button("Import \(bulkSelection.count) Items") {
                    appState.importInboxItems(bulkSelection)
                }
                Divider()
                Button("Move \(bulkSelection.count) to Trash", role: .destructive) {
                    appState.trashInboxItems(bulkSelection)
                }
            }
        }
    }

    private var subtitle: String {
        var parts = [item.modifiedAt.formatted(.dateTime.day().month().hour().minute())]
        if let duration = item.formattedDuration {
            parts.append(duration)
        }
        return parts.joined(separator: " · ")
    }
}

private struct RecordingSidebarRow: View {
    let recording: RecordingRecord

    private var audioURL: URL {
        RecordingStore.shared.audioURL(for: recording)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts = [statusLabel]
        if let duration = recording.resolvedAudioDuration(from: audioURL) {
            parts.append(duration)
        }
        return parts.joined(separator: " · ")
    }

    private var statusLabel: String {
        if let published = recording.summaryVariants.first(where: { $0.status == .published }) {
            return "Published · \(published.options.flow.label)"
        }
        if recording.summaryVariants.contains(where: { $0.status == .ready || $0.status == .stale }) {
            return "Summarized"
        }
        switch recording.transcriptionStatus {
        case .completed:
            return "Transcribed"
        case .failed:
            return "Transcription failed"
        case .inProgress:
            return "Transcribing…"
        case .queued:
            return "Queued"
        case .notStarted:
            return recording.source.label
        }
    }

    private var statusIcon: String {
        switch recording.transcriptionStatus {
        case .completed:
            return recording.summaryVariants.contains(where: { $0.status == .published })
                ? "paperplane.circle.fill"
                : "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .inProgress:
            return "waveform"
        case .queued:
            return "clock"
        case .notStarted:
            return "tray.and.arrow.down"
        }
    }

    private var statusColor: Color {
        switch recording.transcriptionStatus {
        case .completed:
            return .green
        case .failed:
            return .red
        case .inProgress, .queued:
            return .accentColor
        case .notStarted:
            return .secondary
        }
    }
}
