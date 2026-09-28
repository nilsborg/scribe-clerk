import SwiftUI

struct SettingsView: View {
    @State private var whisperPath = AppSettings.shared.whisperBinaryPath
    @State private var defaultModelPath = AppSettings.shared.defaultModelPath
    @State private var voiceActivityDetectionEnabled = AppSettings.shared.voiceActivityDetectionEnabled
    @State private var transcriptionVocabulary = AppSettings.shared.transcriptionVocabulary
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

    private var vadStatus: String {
        if !voiceActivityDetectionEnabled {
            return "Disabled. Whisper will process the full recording."
        }
        return WhisperVAD.isConfigured
            ? "Ready. Silence is skipped before transcription."
            : WhisperVAD.setupHint
    }

    var body: some View {
        Form {
            Section("Whisper") {
                TextField("Whisper binary", text: $whisperPath)
                TextField("Default model", text: $defaultModelPath)

                Toggle("Skip silence with voice activity detection", isOn: $voiceActivityDetectionEnabled)
                Text(vadStatus)
                    .font(.caption)
                    .foregroundStyle(
                        !voiceActivityDetectionEnabled || WhisperVAD.isConfigured
                            ? Color.secondary
                            : Color.red
                    )
                    .fixedSize(horizontal: false, vertical: true)

                Button("Reveal Whisper Models Folder") {
                    try? FileManager.default.createDirectory(
                        at: WhisperModelCatalog.modelsDirectory,
                        withIntermediateDirectories: true
                    )
                    AppSupportPaths.revealInFinder(WhisperModelCatalog.modelsDirectory)
                }

                Text("Transcription vocabulary")
                TextEditor(text: $transcriptionVocabulary)
                    .font(.body)
                    .frame(minHeight: 72)
                Text("Add names, products, abbreviations, and specialist terms—one per line. They are supplied to Whisper as context for every recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .frame(width: 560, height: 620)
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
        .onChange(of: voiceActivityDetectionEnabled) { _, newValue in
            AppSettings.shared.voiceActivityDetectionEnabled = newValue
        }
        .onChange(of: transcriptionVocabulary) { _, newValue in
            AppSettings.shared.transcriptionVocabulary = newValue
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
