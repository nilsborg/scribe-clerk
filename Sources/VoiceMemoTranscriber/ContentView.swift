import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = VoiceMemoListViewModel()
    @State private var selectedMemoID: VoiceMemo.ID?
    @State private var showingSettings = false

    private var selectedMemo: VoiceMemo? {
        guard let selectedMemoID else { return nil }
        return viewModel.memos.first { $0.id == selectedMemoID }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await viewModel.loadMemos()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search memos or transcripts", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await viewModel.loadMemos() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)

                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .padding()

            if viewModel.isLoading && viewModel.memos.isEmpty {
                ProgressView("Loading Voice Memos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.memos.isEmpty {
                ContentUnavailableView {
                    Label("No Voice Memos", systemImage: "mic.slash")
                } description: {
                    Text("Record something in Voice Memos, grant Full Disk Access if needed, then refresh.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.filteredMemos, selection: $selectedMemoID) { memo in
                    MemoRow(memo: memo, status: viewModel.status(for: memo))
                        .tag(memo.id)
                }
            }

            footer
        }
        .navigationTitle("Voice Memos")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await viewModel.transcribePending() }
                } label: {
                    Label("Transcribe New", systemImage: "waveform.badge.plus")
                }
                .disabled(viewModel.pendingCount == 0 || viewModel.isTranscribing)
            }
        }
    }

    private var detailPane: some View {
        Group {
            if let memo = selectedMemo {
                MemoDetailView(
                    memo: memo,
                    status: viewModel.status(for: memo),
                    onTranscribe: {
                        Task { await viewModel.transcribe(memo) }
                    },
                    onReveal: {
                        viewModel.revealInFinder(memo)
                    }
                )
            } else {
                ContentUnavailableView(
                    "Select a memo",
                    systemImage: "sidebar.left",
                    description: Text("Pick a recording to view its transcript.")
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            if viewModel.isTranscribing {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
            } else {
                Text("\(viewModel.memos.count) recordings")
            }

            Spacer()

            if viewModel.pendingCount > 0 {
                Text("\(viewModel.pendingCount) not transcribed")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}

private struct MemoRow: View {
    let memo: VoiceMemo
    let status: TranscriptionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(memo.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                StatusBadge(status: status)
            }

            HStack(spacing: 8) {
                Text(memo.formattedDate)
                Text("•")
                Text(memo.formattedDuration)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct StatusBadge: View {
    let status: TranscriptionStatus

    var body: some View {
        switch status {
        case .notStarted:
            Label("New", systemImage: "circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .help("Not transcribed yet")
        case .inProgress:
            ProgressView()
                .controlSize(.small)
                .help("Transcribing")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Transcribed")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("Transcription failed")
        }
    }
}

private struct MemoDetailView: View {
    let memo: VoiceMemo
    let status: TranscriptionStatus
    let onTranscribe: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(memo.title)
                        .font(.title2.bold())

                    Text("\(memo.formattedDate) · \(memo.formattedDuration)")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reveal in Finder", action: onReveal)

                Button {
                    onTranscribe()
                } label: {
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
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var transcriptContent: some View {
        switch status {
        case .notStarted:
            ContentUnavailableView(
                "No transcript yet",
                systemImage: "text.bubble",
                description: Text("Transcribe this memo with your local Whisper model.")
            )
        case .inProgress:
            VStack(spacing: 12) {
                ProgressView()
                Text("Running whisper-cli on this recording…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .completed(let transcript):
            ScrollView {
                Text(transcript)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript, forType: .string)
                } label: {
                    Label("Copy transcript", systemImage: "doc.on.doc")
                }

                ShareLink(item: transcript) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Transcription failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
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

import AppKit
