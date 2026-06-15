import Foundation

enum AppSupportPaths {
    static let folderName = "ScribeClerk"
    private static let legacyFolderName = "VoiceMemoTranscriber"

    static func directory(named subfolder: String) -> URL {
        let root = applicationSupportRoot()
        let directory = root.appendingPathComponent(subfolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func migrateLegacyDataIfNeeded() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let legacyRoot = appSupport.appendingPathComponent(legacyFolderName, isDirectory: true)
        guard fileManager.fileExists(atPath: legacyRoot.path) else { return }

        let newRoot = applicationSupportRoot()
        try? fileManager.createDirectory(at: newRoot, withIntermediateDirectories: true)

        for subfolder in ["transcripts", "inbox"] {
            let legacyDirectory = legacyRoot.appendingPathComponent(subfolder, isDirectory: true)
            let newDirectory = newRoot.appendingPathComponent(subfolder, isDirectory: true)

            guard fileManager.fileExists(atPath: legacyDirectory.path) else { continue }

            if !fileManager.fileExists(atPath: newDirectory.path) {
                try? fileManager.moveItem(at: legacyDirectory, to: newDirectory)
                continue
            }

            mergeContents(from: legacyDirectory, into: newDirectory)
            try? fileManager.removeItem(at: legacyDirectory)
        }

        if let remaining = try? fileManager.contentsOfDirectory(atPath: legacyRoot.path), remaining.isEmpty {
            try? fileManager.removeItem(at: legacyRoot)
        }
    }

    private static func applicationSupportRoot() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    private static func mergeContents(from source: URL, into destination: URL) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                continue
            }
            try? fileManager.moveItem(at: file, to: target)
        }
    }
}
