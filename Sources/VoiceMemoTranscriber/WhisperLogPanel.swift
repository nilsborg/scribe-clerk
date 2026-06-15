import SwiftUI

struct WhisperLogPanel: View {
    let text: String
    let isRunning: Bool
    let onClear: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Label("Whisper Output", systemImage: "terminal")
                    .font(.headline)

                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Clear", action: onClear)
                    .disabled(text.isEmpty)

                Button("Close", action: onClose)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(displayText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("log-end")
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
                .onChange(of: text) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("log-end", anchor: .bottom)
                    }
                }
            }
        }
        .frame(minHeight: 160, idealHeight: 220, maxHeight: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var displayText: String {
        if text.isEmpty {
            return isRunning ? "Waiting for whisper-cli output…" : "No whisper output yet."
        }
        return text
    }
}
