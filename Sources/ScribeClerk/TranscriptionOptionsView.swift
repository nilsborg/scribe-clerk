import SwiftUI

enum TranscriptionRequest: Identifiable {
    case files([URL], title: String)
    case recordingIDs([String], title: String)

    var id: String {
        switch self {
        case .files(let urls, _):
            return urls.map(\.absoluteString).joined(separator: "|")
        case .recordingIDs(let ids, _):
            return ids.joined(separator: "|")
        }
    }

    var title: String {
        switch self {
        case .files(_, let title), .recordingIDs(_, let title):
            return title
        }
    }

    var urls: [URL] {
        switch self {
        case .files(let urls, _):
            return urls
        case .recordingIDs:
            return []
        }
    }

    var recordingCount: Int {
        switch self {
        case .files(let urls, _):
            return urls.count
        case .recordingIDs(let ids, _):
            return ids.count
        }
    }
}

struct TranscriptionOptionsView: View {
    let request: TranscriptionRequest
    let queueIsActive: Bool
    let pendingQueueCount: Int
    let onCancel: () -> Void
    let onStart: (TranscriptionOptions) -> Void

    @State private var language: String
    @State private var modelPath: String
    @State private var usesCustomModel: Bool
    @State private var identifySpeakers = false
    // 0 = auto-detect; 2…10 = a known speaker count hint.
    @State private var speakerCount = 0

    private let availableModels: [String]

    init(
        request: TranscriptionRequest,
        queueIsActive: Bool = false,
        pendingQueueCount: Int = 0,
        onCancel: @escaping () -> Void,
        onStart: @escaping (TranscriptionOptions) -> Void
    ) {
        self.request = request
        self.queueIsActive = queueIsActive
        self.pendingQueueCount = pendingQueueCount
        self.onCancel = onCancel
        self.onStart = onStart

        let defaults = AppSettings.shared.defaultTranscriptionOptions()
        let models = WhisperModelCatalog.availableModels(defaultPath: defaults.modelPath)
        availableModels = models

        _language = State(initialValue: defaults.language)
        _usesCustomModel = State(initialValue: !models.contains(defaults.modelPath))
        _modelPath = State(initialValue: defaults.modelPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.title)
                .font(.title3.bold())

            Form {
                Section("Language") {
                    Picker("Quick pick", selection: $language) {
                        ForEach(TranscriptionLanguageOption.options.filter {
                            TranscriptionLanguageOption.quickPickCodes.contains($0.code)
                        }) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Picker("More languages", selection: $language) {
                        ForEach(TranscriptionLanguageOption.options) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                }

                Section("Speaker detection") {
                    Toggle("Identify speakers", isOn: $identifySpeakers)
                    Text("Runs a separate diarization pass and labels the transcript by speaker (Speaker 1, Speaker 2…). Works with any language or model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if identifySpeakers {
                        Picker("Speakers", selection: $speakerCount) {
                            Text("Auto-detect").tag(0)
                            ForEach(2...10, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        Text("If you know how many people were talking, set it here for more accurate labels. Otherwise leave on Auto-detect.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if identifySpeakers && !SpeakerDiarizer.isConfigured {
                        Text(SpeakerDiarizer.setupHint)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Model") {
                    if availableModels.isEmpty {
                        TextField("Model path", text: $modelPath)
                    } else if usesCustomModel {
                        TextField("Model path", text: $modelPath)

                        Button("Choose from installed models") {
                            usesCustomModel = false
                            modelPath = availableModels[0]
                        }
                    } else {
                        Picker("Model", selection: $modelPath) {
                            ForEach(availableModels, id: \.self) { path in
                                Text(WhisperModelCatalog.displayName(for: path))
                                    .tag(path)
                            }
                        }

                        Button("Use custom model path…") {
                            usesCustomModel = true
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(startButtonTitle) {
                    onStart(resolvedOptions())
                }
                .keyboardShortcut(.defaultAction)
                .disabled(startIsDisabled)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func resolvedOptions() -> TranscriptionOptions {
        TranscriptionOptions(
            language: language,
            modelPath: modelPath.trimmingCharacters(in: .whitespacesAndNewlines),
            identifySpeakers: identifySpeakers,
            speakerCount: (identifySpeakers && speakerCount > 0) ? speakerCount : nil
        )
    }

    private var startIsDisabled: Bool {
        if identifySpeakers && !SpeakerDiarizer.isConfigured {
            return true
        }
        return modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var startButtonTitle: String {
        if queueIsActive {
            return "Add to Queue"
        }
        return request.recordingCount > 1 ? "Start Queue" : "Transcribe"
    }
}
