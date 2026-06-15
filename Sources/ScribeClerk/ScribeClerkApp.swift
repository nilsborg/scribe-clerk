import SwiftUI

@main
struct ScribeClerkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 960, height: 680)

        Settings {
            SettingsView()
        }
    }
}
