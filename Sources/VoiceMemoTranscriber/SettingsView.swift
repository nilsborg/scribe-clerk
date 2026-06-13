import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var whisperPath = AppSettings.shared.whisperBinaryPath
    @State private var modelPath = AppSettings.shared.modelPath
    @State private var language = AppSettings.shared.language

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2.bold())

            Form {
                TextField("Whisper binary", text: $whisperPath)
                TextField("Model path", text: $modelPath)
                TextField("Language (auto, en, de, …)", text: $language)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy")
                    .font(.headline)

                Text("Voice Memos lives in a protected folder. Add this app to System Settings > Privacy & Security > Full Disk Access.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Full Disk Access Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    AppSettings.shared.whisperBinaryPath = whisperPath
                    AppSettings.shared.modelPath = modelPath
                    AppSettings.shared.language = language
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

import AppKit
