import SwiftUI

struct SettingsView: View {
    @State private var whisperPath = AppSettings.shared.whisperBinaryPath
    @State private var defaultModelPath = AppSettings.shared.defaultModelPath

    var body: some View {
        Form {
            Section("Whisper") {
                TextField("Whisper binary", text: $whisperPath)
                TextField("Default model", text: $defaultModelPath)
            }

            Section("How to use") {
                Text("Drag recordings from Voice Memos into the app window, or use Open Audio in the toolbar.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 480, height: 220)
        .onChange(of: whisperPath) { _, newValue in
            AppSettings.shared.whisperBinaryPath = newValue
        }
        .onChange(of: defaultModelPath) { _, newValue in
            AppSettings.shared.defaultModelPath = newValue
        }
    }
}
