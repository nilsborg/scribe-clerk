import SwiftUI

struct SummaryOptionsView: View {
    let recordingIDs: [String]
    let sampleRecording: RecordingRecord?
    let regenerate: Bool
    let queueIsActive: Bool
    let onCancel: () -> Void
    let onStart: (SummarizerOptions) -> Void

    @State private var flow: SummarizerFlow
    @State private var language: SummarizerLanguage

    init(
        recordingIDs: [String],
        sampleRecording: RecordingRecord?,
        regenerate: Bool,
        queueIsActive: Bool,
        onCancel: @escaping () -> Void,
        onStart: @escaping (SummarizerOptions) -> Void
    ) {
        self.recordingIDs = recordingIDs
        self.sampleRecording = sampleRecording
        self.regenerate = regenerate
        self.queueIsActive = queueIsActive
        self.onCancel = onCancel
        self.onStart = onStart

        let defaults = AppSettings.shared
        _flow = State(initialValue: defaults.defaultSummarizerFlow)
        _language = State(initialValue: sampleRecording?.preferredSummarizerLanguage ?? .english)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.bold())

            if recordingIDs.count == 1, let sampleRecording {
                Text(sampleRecording.title)
                    .foregroundStyle(.secondary)
            } else if recordingIDs.count > 1 {
                Text("\(recordingIDs.count) recordings")
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
                Button(startButtonTitle) {
                    onStart(SummarizerOptions(flow: flow, language: language))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var title: String {
        if regenerate {
            return recordingIDs.count > 1 ? "Re-summarize \(recordingIDs.count) recordings" : "Re-summarize"
        }
        return recordingIDs.count > 1 ? "Summarize \(recordingIDs.count) recordings" : "Summarize"
    }

    private var startButtonTitle: String {
        if queueIsActive {
            return "Add to Queue"
        }
        return recordingIDs.count > 1 ? "Start Queue" : "Generate Summary"
    }
}
