import SwiftUI

struct SummarizerOptionsView: View {
    let request: SummarizerRequest
    let onCancel: () -> Void
    let onStart: (SummarizerOptions) -> Void

    @State private var flow: SummarizerFlow
    @State private var language: SummarizerLanguage

    init(
        request: SummarizerRequest,
        onCancel: @escaping () -> Void,
        onStart: @escaping (SummarizerOptions) -> Void
    ) {
        self.request = request
        self.onCancel = onCancel
        self.onStart = onStart

        let defaults = AppSettings.shared.defaultSummarizerOptions(for: request.record)
        _flow = State(initialValue: defaults.flow)
        _language = State(initialValue: defaults.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Summarize transcript")
                    .font(.title2.bold())

                Text(request.job.displayName)
                    .foregroundStyle(.secondary)
            }

            Form {
                Picker("Pipeline", selection: $flow) {
                    ForEach(SummarizerFlow.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                Picker("Summary language", selection: $language) {
                    ForEach(SummarizerLanguage.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
            .formStyle(.grouped)

            Text("Exports the transcript to meeting-summaries-to-notion, runs the OpenRouter summary, and creates a Notion page.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Summarize") {
                    onStart(SummarizerOptions(flow: flow, language: language))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
