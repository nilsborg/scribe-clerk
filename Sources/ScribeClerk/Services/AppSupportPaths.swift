import Foundation
import AppKit

enum AppSupportPaths {
    static let folderName = "ScribeClerk"
    private static let legacyFolderName = "VoiceMemoTranscriber"

    static func directory(named subfolder: String) -> URL {
        let root = applicationSupportRoot
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

        let newRoot = applicationSupportRoot
        try? fileManager.createDirectory(at: newRoot, withIntermediateDirectories: true)

        for subfolder in ["transcripts", "inbox", "recordings"] {
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

    static var applicationSupportRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    static var inboxURL: URL {
        directory(named: "inbox")
    }

    static var recordingsURL: URL {
        directory(named: "recordings")
    }

    static var adapterEnvURL: URL {
        directory(named: "config").appendingPathComponent("adapter.env")
    }

    static func migrateAdapterEnvIfNeeded() -> URL {
        let canonical = adapterEnvURL
        let fileManager = FileManager.default

        let sources = adapterEnvMigrationSources()
        let configuredSource = sources.first { hasConfiguredAdapterCredentials(at: $0) }

        if let configuredSource,
           !configuredSource.standardizedFileURL.path.elementsEqual(canonical.standardizedFileURL.path),
           let data = try? Data(contentsOf: configuredSource) {
            try? fileManager.createDirectory(
                at: canonical.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: canonical, options: .atomic)
        }

        return ensureAdapterEnvFile(at: canonical)
    }

    static func resolvedAdapterEnvPath() -> String {
        let canonical = adapterEnvURL

        if let saved = UserDefaults.standard.string(forKey: "adapterEnvPath") {
            let savedURL = URL(fileURLWithPath: saved)
            if fileManager.fileExists(atPath: savedURL.path),
               hasConfiguredAdapterCredentials(at: savedURL) {
                return savedURL.path
            }
        }

        for candidate in adapterEnvMigrationSources() + [canonical] {
            if hasConfiguredAdapterCredentials(at: candidate) {
                return candidate.path
            }
        }

        return migrateAdapterEnvIfNeeded().path
    }

    static func ensureAdapterEnvFile(at url: URL = adapterEnvURL) -> URL {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: url.path) else { return url }

        let configuredCandidates = adapterEnvMigrationSources()
        if let configured = configuredCandidates.first(where: { hasConfiguredAdapterCredentials(at: $0) }) {
            try? fileManager.copyItem(at: configured, to: url)
            return url
        }

        let exampleCandidates = [
            directory.appendingPathComponent(".env.example"),
            AdapterPaths.meetingSummariesToNotionRoot.appendingPathComponent(".env.example"),
        ]

        if let example = exampleCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            try? fileManager.copyItem(at: example, to: url)
            return url
        }

        let template = """
        OPENROUTER_API_KEY=""
        """
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            + "\n"
        try? template.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openInDefaultEditor(_ url: URL) {
        _ = migrateAdapterEnvIfNeeded()
        let fileURL = URL(fileURLWithPath: resolvedAdapterEnvPath())

        if let textEditURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(
                [fileURL],
                withApplicationAt: textEditURL,
                configuration: configuration
            ) { _, error in
                if error != nil {
                    DispatchQueue.main.async {
                        revealInFinder(fileURL.deletingLastPathComponent())
                    }
                }
            }
            return
        }

        let opened = NSWorkspace.shared.open(fileURL)
        if !opened {
            revealInFinder(fileURL.deletingLastPathComponent())
        }
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

    private static var fileManager: FileManager { .default }

    private static func adapterEnvMigrationSources() -> [URL] {
        var urls: [URL] = []

        let repoEnv = AdapterPaths.envFileURL
        urls.append(repoEnv)

        let flatSupportEnv = applicationSupportRoot.appendingPathComponent("adapter.env")
        urls.append(flatSupportEnv)

        if let saved = UserDefaults.standard.string(forKey: "adapterEnvPath") {
            urls.append(URL(fileURLWithPath: saved))
        }

        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return false }
            return fileManager.fileExists(atPath: path)
        }
    }

    private static func hasConfiguredAdapterCredentials(at url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("OPENROUTER_API_KEY") else { continue }
            guard let value = trimmed.split(separator: "=", maxSplits: 1).last else { return false }
            return isConfiguredEnvValue(String(value))
        }

        return false
    }

    private static func isConfiguredEnvValue(_ raw: String) -> Bool {
        let value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return !value.isEmpty && value != "xxx"
    }
}
