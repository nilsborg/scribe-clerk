import SwiftUI

struct MultiSelectionView: View {
    let recordings: [RecordingRecord]
    @ObservedObject var appState: AppState
    @State private var showDeleteConfirmation = false

    private var actions: BulkRecordingActions.Availability {
        BulkRecordingActions.availability(for: recordings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(recordings.count) recordings selected")
                    .font(.title2.bold())
                Text("Run an action on every selected recording, or pick a single one to see its details.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            Divider()

            HStack(spacing: 10) {
                if !actions.transcribeIDs.isEmpty {
                    Button {
                        appState.beginBulkTranscription(for: actions.transcribeIDs)
                    } label: {
                        Label("Transcribe \(actions.transcribeIDs.count)", systemImage: "waveform")
                    }
                }

                if !actions.summarizeIDs.isEmpty {
                    Button {
                        appState.beginBulkSummary(for: actions.summarizeIDs)
                    } label: {
                        Label("Summarize \(actions.summarizeIDs.count)", systemImage: "text.append")
                    }
                }

                if !actions.resummarizeIDs.isEmpty {
                    Button {
                        appState.beginBulkSummary(for: actions.resummarizeIDs, regenerate: true)
                    } label: {
                        Label("Re-summarize \(actions.resummarizeIDs.count)", systemImage: "text.append")
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete \(recordings.count)", systemImage: "trash")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()

            List {
                ForEach(recordings) { recording in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recording.title)
                                .lineLimit(1)
                            Text(recording.displayDate, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(recording: recording, appState: appState)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.selectRecording(recording.id)
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "Delete \(recordings.count) recordings?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(recordings.count)", role: .destructive) {
                appState.deleteRecordings(recordings.map(\.id))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the recordings, transcripts, and summaries from your library.")
        }
    }
}
