import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject private var appState = AppState.shared
    @Environment(\.openWindow) private var openWindow
    @State private var showFileImporter = false

    var body: some View {
        NavigationSplitView {
            RecordingLibraryView(appState: appState) {
                showFileImporter = true
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            Group {
                let selected = appState.selectedRecordings
                if selected.count > 1 {
                    MultiSelectionView(recordings: selected, appState: appState)
                } else if let recording = appState.selectedRecording {
                    RecordingDetailView(recording: recording, appState: appState)
                } else {
                    emptyState
                }
            }
            .frame(minWidth: 520, minHeight: 560)
            .onDrop(of: AudioDropTypes.accepted, isTargeted: nil, perform: handleWindowDrop)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    openWindow(id: WhisperLogWindow.id)
                } label: {
                    Label("Whisper Output", systemImage: "terminal")
                }
                .help("Open whisper-cli console output")
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: AudioFileFilter.acceptedTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                appState.addFilesToInbox(urls)
            }
        }
        .sheet(item: $appState.pendingTranscriptionRequest) { request in
            TranscriptionOptionsView(
                request: request,
                queueIsActive: appState.isTranscriptionActive,
                pendingQueueCount: appState.pendingTranscriptionCount,
                onCancel: { appState.pendingTranscriptionRequest = nil },
                onStart: { options in
                    appState.pendingTranscriptionRequest = nil
                    if let recordingID = recordingID(for: request.urls.first) {
                        appState.enqueueTranscription(recordingID: recordingID, options: options)
                    }
                }
            )
        }
        .sheet(item: $appState.summaryRequest) { request in
            SummaryOptionsView(
                recording: appState.recordings.first { $0.id == request.recordingID },
                regenerate: request.regenerate,
                queueIsActive: appState.isSummaryActive,
                onCancel: { appState.summaryRequest = nil },
                onStart: { options in
                    appState.summaryRequest = nil
                    appState.enqueueSummary(
                        recordingID: request.recordingID,
                        options: options,
                        regenerate: request.regenerate
                    )
                }
            )
        }
        .sheet(item: $appState.publishRequest) { request in
            PublishConfirmationView(
                recording: appState.recordings.first { $0.id == request.recordingID },
                variantID: request.variantID,
                onCancel: { appState.publishRequest = nil },
                onPublish: {
                    appState.publishRequest = nil
                    appState.enqueuePublish(recordingID: request.recordingID, variantID: request.variantID)
                }
            )
        }
        .alert("Duplicate recording", isPresented: duplicateBinding) {
            Button("Open Existing", role: .cancel) {
                appState.confirmDuplicateImport(createAnyway: false)
            }
            Button("Import Anyway") {
                appState.confirmDuplicateImport(createAnyway: true)
            }
        } message: {
            if let prompt = appState.duplicateImportPrompt {
                Text("“\(prompt.existing.title)” already exists in your library.")
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .alert("Success", isPresented: successBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.successMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshInbox()
            if let selectedID = appState.selectedRecordingID {
                appState.reloadTranscript(for: selectedID)
            }
        }
    }

    private var emptyState: some View {
        AudioDropZone(
            title: "Drop audio into the inbox",
            subtitle: "New files land in the inbox. Import them into your library when you're ready."
        ) { urls in
            appState.addFilesToInbox(urls)
        }
    }

    private func handleWindowDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            let urls = await DroppedFileLoader.loadURLs(from: providers)
            guard !urls.isEmpty else { return }
            await MainActor.run {
                appState.addFilesToInbox(urls)
            }
        }
        return true
    }

    private func recordingID(for audioURL: URL?) -> String? {
        guard let audioURL else { return nil }
        return appState.recordings.first {
            AppState.shared.audioURL(for: $0)?.standardizedFileURL == audioURL.standardizedFileURL
        }?.id
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )
    }

    private var successBinding: Binding<Bool> {
        Binding(
            get: { appState.successMessage != nil },
            set: { if !$0 { appState.successMessage = nil } }
        )
    }

    private var duplicateBinding: Binding<Bool> {
        Binding(
            get: { appState.duplicateImportPrompt != nil },
            set: { if !$0 { appState.duplicateImportPrompt = nil } }
        )
    }
}

import AppKit
