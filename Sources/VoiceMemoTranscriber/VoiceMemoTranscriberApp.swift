import SwiftUI

@main
struct VoiceMemoTranscriberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 720, height: 640)

        Settings {
            SettingsView()
        }
    }
}
