import SwiftUI

struct WhisperLogWindowView: View {
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Label("Whisper Output", systemImage: "terminal")
                    .font(.headline)

                if appState.isTranscriptionActive {
                    VStack(alignment: .leading, spacing: 6) {
                        if let progress = appState.transcriptionProgress {
                            ProgressView(value: progress) {
                                Text(appState.transcriptionProgressLabel(
                                    for: appState.activeTranscriptionRecordingID ?? ""
                                ))
                            }
                            .progressViewStyle(.linear)
                            .frame(width: 220)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                Spacer()

                Button("Clear", action: appState.clearWhisperLog)
                    .disabled(appState.whisperLogText.isEmpty)

                Button("Close") {
                    dismissWindow(id: WhisperLogWindow.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(displayText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .id("log-end")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: appState.whisperLogText) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("log-end", anchor: .bottom)
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 320)
    }

    private var displayText: String {
        if appState.whisperLogText.isEmpty {
            return appState.isTranscriptionActive
                ? "Waiting for whisper-cli output…"
                : "No whisper output yet."
        }
        return appState.whisperLogText
    }
}

enum WhisperLogWindow {
    static let id = "whisper-log"
}
