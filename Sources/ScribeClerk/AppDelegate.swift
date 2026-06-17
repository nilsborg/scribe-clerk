import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSupportPaths.migrateLegacyDataIfNeeded()
        AppState.shared.loadLibrary()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppState.shared.isAnyJobActive else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Jobs in progress"
        alert.informativeText = AppState.shared.quitWarningMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Anyway")

        if alert.runModal() == .alertSecondButtonReturn {
            AppState.shared.stopAllQueues()
            return .terminateNow
        }

        return .terminateCancel
    }
}
