import SwiftUI

struct SettingsView: View {
    @State private var whisperPath = AppSettings.shared.whisperBinaryPath
    @State private var defaultModelPath = AppSettings.shared.defaultModelPath
    @State private var summarizerRepoPath = AppSettings.shared.summarizerRepoPath
    @State private var denoPath = AppSettings.shared.denoBinaryPath
    @State private var defaultSummarizerFlow = AppSettings.shared.defaultSummarizerFlow

    var body: some View {
        Form {
            Section("Whisper") {
                TextField("Whisper binary", text: $whisperPath)
                TextField("Default model", text: $defaultModelPath)
            }

            Section("Summarizer") {
                TextField("Meeting summaries repo", text: $summarizerRepoPath)
                TextField("Deno binary", text: $denoPath)

                Picker("Default pipeline", selection: $defaultSummarizerFlow) {
                    ForEach(SummarizerFlow.allCases) { flow in
                        Text(flow.label).tag(flow)
                    }
                }
            }

            Section("How to use") {
                Text("Drag recordings from Voice Memos into the app window, transcribe, then use Summarize to send the transcript to meeting-summaries-to-notion.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 360)
        .onChange(of: whisperPath) { _, newValue in
            AppSettings.shared.whisperBinaryPath = newValue
        }
        .onChange(of: defaultModelPath) { _, newValue in
            AppSettings.shared.defaultModelPath = newValue
        }
        .onChange(of: summarizerRepoPath) { _, newValue in
            AppSettings.shared.summarizerRepoPath = newValue
        }
        .onChange(of: denoPath) { _, newValue in
            AppSettings.shared.denoBinaryPath = newValue
        }
        .onChange(of: defaultSummarizerFlow) { _, newValue in
            AppSettings.shared.defaultSummarizerFlow = newValue
        }
    }
}
