import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.loadHistory()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppState.shared.isQueueActive else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Transcription in progress"
        alert.informativeText = AppState.shared.transcriptionQuitWarningMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Anyway")

        if alert.runModal() == .alertSecondButtonReturn {
            AppState.shared.stopQueue()
            return .terminateNow
        }

        return .terminateCancel
    }
}
