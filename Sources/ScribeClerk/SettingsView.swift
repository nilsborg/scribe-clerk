import SwiftUI

struct SettingsView: View {
    @State private var whisperPath = AppSettings.shared.whisperBinaryPath
    @State private var defaultModelPath = AppSettings.shared.defaultModelPath
    @State private var diarizationPath = AppSettings.shared.diarizationBinaryPath
    @State private var denoPath = AppSettings.shared.denoBinaryPath
    @State private var adapterEnvPath = AppSettings.shared.adapterEnvPath
    @State private var defaultSummarizerFlow = AppSettings.shared.defaultSummarizerFlow

    private var diarizationStatus: String {
        if SpeakerDiarizer.isConfigured {
            return "Ready. Models found in \(SpeakerDiarizer.modelsDirectory.path)."
        }
        return SpeakerDiarizer.setupHint
    }

    var body: some View {
        Form {
            Section("Whisper") {
                TextField("Whisper binary", text: $whisperPath)
                TextField("Default model", text: $defaultModelPath)
            }

            Section("Speaker detection") {
                TextField("sherpa-onnx binary", text: $diarizationPath)
                Text(diarizationStatus)
                    .font(.caption)
                    .foregroundStyle(SpeakerDiarizer.isConfigured ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Reveal Models Folder") {
                    try? FileManager.default.createDirectory(
                        at: SpeakerDiarizer.modelsDirectory,
                        withIntermediateDirectories: true
                    )
                    AppSupportPaths.revealInFinder(SpeakerDiarizer.modelsDirectory)
                }
            }

            Section("Summarizer Adapter") {
                TextField("Deno binary", text: $denoPath)
                TextField("Adapter .env file", text: $adapterEnvPath)

                Picker("Default pipeline", selection: $defaultSummarizerFlow) {
                    ForEach(SummarizerFlow.allCases) { flow in
                        Text(flow.label).tag(flow)
                    }
                }

                Button("Open .env in TextEdit") {
                    let envURL = URL(fileURLWithPath: AppSettings.shared.adapterEnvPath)
                    AppSupportPaths.openInDefaultEditor(envURL)
                    adapterEnvPath = AppSettings.shared.adapterEnvPath
                }

                Button("Reveal Adapter Folder") {
                    AppSupportPaths.revealInFinder(AdapterPaths.meetingSummariesToNotionRoot)
                }

                Button("Reveal Inbox Folder") {
                    AppSupportPaths.revealInFinder(AppSupportPaths.inboxURL)
                }
            }

            Section("How to use") {
                Text("Drop audio into the inbox, import into your library, transcribe with Whisper, then generate editable summaries.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 540, height: 420)
        .onAppear {
            let resolved = AppSettings.shared.adapterEnvPath
            adapterEnvPath = resolved
        }
        .onChange(of: whisperPath) { _, newValue in
            AppSettings.shared.whisperBinaryPath = newValue
        }
        .onChange(of: defaultModelPath) { _, newValue in
            AppSettings.shared.defaultModelPath = newValue
        }
        .onChange(of: diarizationPath) { _, newValue in
            AppSettings.shared.diarizationBinaryPath = newValue
        }
        .onChange(of: denoPath) { _, newValue in
            AppSettings.shared.denoBinaryPath = newValue
        }
        .onChange(of: adapterEnvPath) { _, newValue in
            AppSettings.shared.adapterEnvPath = newValue
        }
        .onChange(of: defaultSummarizerFlow) { _, newValue in
            AppSettings.shared.defaultSummarizerFlow = newValue
        }
    }
}
