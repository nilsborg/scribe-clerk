import SwiftUI

enum TranscriptionRequest: Identifiable {
    case files([URL], title: String)

    var id: String {
        switch self {
        case .files(let urls, _):
            return urls.map(\.absoluteString).joined(separator: "|")
        }
    }

    var title: String {
        switch self {
        case .files(_, let title):
            return title
        }
    }

    var urls: [URL] {
        switch self {
        case .files(let urls, _):
            return urls
        }
    }
}

struct TranscriptionOptionsView: View {
    let request: TranscriptionRequest
    let onCancel: () -> Void
    let onStart: (TranscriptionOptions) -> Void

    @State private var language: String
    @State private var modelPath: String
    @State private var usesCustomModel: Bool

    private let availableModels: [String]

    init(
        request: TranscriptionRequest,
        onCancel: @escaping () -> Void,
        onStart: @escaping (TranscriptionOptions) -> Void
    ) {
        self.request = request
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

                Button("Transcribe") {
                    onStart(
                        TranscriptionOptions(
                            language: language,
                            modelPath: modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
