import Foundation

enum MeetingSummarizerError: LocalizedError {
    case missingRepo(String)
    case missingDeno(String)
    case missingRerunScript(String)
    case exportFailed(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRepo(let path):
            return "Meeting summaries repo not found at \(path)."
        case .missingDeno(let path):
            return "Deno not found at \(path)."
        case .missingRerunScript(let path):
            return "rerun.ts not found at \(path)."
        case .exportFailed(let message):
            return message
        case .processFailed(let message):
            return message
        }
    }
}

struct MeetingSummarizerService {
    private let fileManager = FileManager.default

    func exportTranscript(
        text: String,
        createdAt: Date,
        sourceName: String?,
        repoRoot: URL
    ) throws -> (fileURL: URL, searchTerm: String) {
        let sourceFolder = repoRoot.appendingPathComponent("source", isDirectory: true)

        guard fileManager.fileExists(atPath: repoRoot.path) else {
            throw MeetingSummarizerError.missingRepo(repoRoot.path)
        }

        try fileManager.createDirectory(at: sourceFolder, withIntermediateDirectories: true)

        let stamp = Self.transcriptStampFormatter.string(from: createdAt)
        let baseName = "\(stamp) Transcription"
        let fileName = uniqueFileName(baseName: baseName, in: sourceFolder)
        let fileURL = sourceFolder.appendingPathComponent(fileName)

        guard let data = text.data(using: .utf8) else {
            throw MeetingSummarizerError.exportFailed("Could not encode transcript as UTF-8.")
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw MeetingSummarizerError.exportFailed(error.localizedDescription)
        }

        let searchTerm = fileName.replacingOccurrences(of: ".txt", with: "")
        return (fileURL, searchTerm)
    }

    func runPipeline(
        searchTerm: String,
        options: SummarizerOptions,
        repoRoot: URL,
        denoPath: String
    ) async throws {
        let rerunScript = repoRoot.appendingPathComponent("rerun.ts")

        guard fileManager.fileExists(atPath: denoPath) else {
            throw MeetingSummarizerError.missingDeno(denoPath)
        }

        guard fileManager.fileExists(atPath: rerunScript.path) else {
            throw MeetingSummarizerError.missingRerunScript(rerunScript.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: denoPath)
        process.currentDirectoryURL = repoRoot
        process.arguments = [
            "run",
            "--allow-all",
            rerunScript.path,
            "--flow", options.flow.rawValue,
            "--lang", options.language.rawValue,
            searchTerm,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { process in
                let stdout = String(
                    data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if process.terminationStatus == 0,
                   stdout.contains("✅ Success!") {
                    continuation.resume()
                    return
                }

                continuation.resume(
                    throwing: MeetingSummarizerError.processFailed(
                        Self.pipelineErrorMessage(
                            stdout: stdout,
                            stderr: stderr,
                            exitCode: process.terminationStatus
                        )
                    )
                )
            }
        }
    }

    private static func pipelineErrorMessage(
        stdout: String,
        stderr: String,
        exitCode: Int32
    ) -> String {
        let combined = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        if combined.contains("Key limit exceeded") {
            return "OpenRouter API key limit exceeded. Check billing and limits at openrouter.ai."
        }

        if let openRouterMessage = firstMatch(
            in: combined,
            pattern: #"OpenRouter API error[^:]*:\s*[^,]+,\s*(\{.*\})"#
        ),
           let data = openRouterMessage.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return "OpenRouter: \(message)"
        }

        if let line = combined
            .components(separatedBy: .newlines)
            .first(where: { $0.contains("Error during summarization") || $0.contains("OpenRouter API error") }) {
            return line
        }

        if !combined.isEmpty {
            return combined
        }

        return "Summarizer exited with code \(exitCode)."
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private func uniqueFileName(baseName: String, in folder: URL) -> String {
        var candidate = "\(baseName).txt"
        var counter = 2

        while fileManager.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = "\(baseName) \(counter).txt"
            counter += 1
        }

        return candidate
    }

    private static let transcriptStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd HHmm"
        return formatter
    }()
}
