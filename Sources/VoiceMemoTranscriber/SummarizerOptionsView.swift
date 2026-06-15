import SwiftUI

struct SummarizerOptionsView: View {
    let request: SummarizerRequest
    let queueIsActive: Bool
    let onCancel: () -> Void
    let onStart: (SummarizerOptions) -> Void

    @State private var flow: SummarizerFlow
    @State private var language: SummarizerLanguage

    init(
        request: SummarizerRequest,
        queueIsActive: Bool = false,
        onCancel: @escaping () -> Void,
        onStart: @escaping (SummarizerOptions) -> Void
    ) {
        self.request = request
        self.queueIsActive = queueIsActive
        self.onCancel = onCancel
        self.onStart = onStart

        let defaults = AppSettings.shared.defaultSummarizerOptions(for: request.items[0].record)
        _flow = State(initialValue: defaults.flow)
        _language = State(initialValue: defaults.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Summarize transcript")
                    .font(.title2.bold())

                Text(request.title)
                    .foregroundStyle(.secondary)

                if request.items.count > 1 {
                    Text(request.items.map(\.job.displayName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                }
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

            Text("Exports each transcript to meeting-summaries-to-notion and creates Notion pages in order.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(startButtonTitle) {
                    onStart(SummarizerOptions(flow: flow, language: language))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var startButtonTitle: String {
        if queueIsActive {
            return "Add to Queue"
        }
        return request.items.count > 1 ? "Start Summarize Queue" : "Summarize"
    }
}
