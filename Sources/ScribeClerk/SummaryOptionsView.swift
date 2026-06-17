import SwiftUI

struct SummaryOptionsView: View {
    let recording: RecordingRecord?
    let regenerate: Bool
    let queueIsActive: Bool
    let onCancel: () -> Void
    let onStart: (SummarizerOptions) -> Void

    @State private var flow: SummarizerFlow
    @State private var language: SummarizerLanguage

    init(
        recording: RecordingRecord?,
        regenerate: Bool,
        queueIsActive: Bool,
        onCancel: @escaping () -> Void,
        onStart: @escaping (SummarizerOptions) -> Void
    ) {
        self.recording = recording
        self.regenerate = regenerate
        self.queueIsActive = queueIsActive
        self.onCancel = onCancel
        self.onStart = onStart

        let defaults = AppSettings.shared
        _flow = State(initialValue: defaults.defaultSummarizerFlow)
        _language = State(initialValue: .english)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(regenerate ? "Re-summarize" : "Summarize")
                .font(.title3.bold())

            if let recording {
                Text(recording.title)
                    .foregroundStyle(.secondary)
            }

            Form {
                Picker("Flow", selection: $flow) {
                    ForEach(SummarizerFlow.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }

                Picker("Summary language", selection: $language) {
                    ForEach(SummarizerLanguage.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button(queueIsActive ? "Add to Queue" : "Generate Summary") {
                    onStart(SummarizerOptions(flow: flow, language: language))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct PublishConfirmationView: View {
    let recording: RecordingRecord?
    let variantID: String
    let onCancel: () -> Void
    let onPublish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send to Notion")
                .font(.title3.bold())

            if let recording,
               let variant = recording.summaryVariants.first(where: { $0.id == variantID }) {
                Text("Publish \(variant.flow.label) (\(variant.language.label)) for “\(recording.title)”")
                    .foregroundStyle(.secondary)
            }

            Text("This creates a Notion page with the summary and a linked transcript sub-page.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Publish", action: onPublish)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
