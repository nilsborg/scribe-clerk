import Foundation

enum AudioInbox {
    private static var directory: URL {
        AppSupportPaths.directory(named: "inbox")
    }

    /// Ensures the file lives in the inbox folder, copying when needed.
    static func add(_ url: URL) -> URL {
        let inboxDir = directory.standardizedFileURL
        if url.deletingLastPathComponent().standardizedFileURL == inboxDir {
            return url
        }

        let destination = directory.appendingPathComponent(url.lastPathComponent)
        let uniqueDestination = uniqueURL(for: destination)

        do {
            if FileManager.default.fileExists(atPath: uniqueDestination.path) {
                try FileManager.default.removeItem(at: uniqueDestination)
            }
            try FileManager.default.copyItem(at: url, to: uniqueDestination)
            return uniqueDestination
        } catch {
            return persist(url)
        }
    }

    /// Copies dragged files into app storage so they remain readable after the drag session ends.
    static func persist(_ url: URL) -> URL {
        guard shouldCopy(url) else { return url }

        let destination = directory.appendingPathComponent(url.lastPathComponent)
        let uniqueDestination = uniqueURL(for: destination)

        do {
            if FileManager.default.fileExists(atPath: uniqueDestination.path) {
                try FileManager.default.removeItem(at: uniqueDestination)
            }
            try FileManager.default.copyItem(at: url, to: uniqueDestination)
            return uniqueDestination
        } catch {
            return url
        }
    }

    private static func shouldCopy(_ url: URL) -> Bool {
        let path = url.path
        if path.contains(FileManager.default.temporaryDirectory.path) {
            return true
        }
        if path.contains("/var/folders/") {
            return true
        }
        return false
    }

    private static func uniqueURL(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }

        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 2

        while true {
            let name = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
