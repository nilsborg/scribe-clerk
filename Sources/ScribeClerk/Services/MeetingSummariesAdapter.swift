import Foundation

struct SummaryResult: Equatable {
    let title: String?
    let summaryPath: URL
    let markdown: String
}

protocol SummaryAdapter {
    func generateSummary(
        transcriptPath: URL,
        summaryPath: URL,
        recordingTitle: String?,
        options: SummarizerOptions,
        skipCache: Bool
    ) async throws -> SummaryResult

    func generateTitle(transcriptPath: URL) async throws -> String
}

enum AdapterError: LocalizedError {
    case missingDeno(String)
    case missingRunScript(String)
    case missingAdapterRoot(String)
    case invalidResponse(String)
    case adapterFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDeno(let path):
            return "Deno not found at \(path)."
        case .missingRunScript(let path):
            return "Adapter run script not found at \(path)."
        case .missingAdapterRoot(let path):
            return "Meeting summaries adapter not found at \(path)."
        case .invalidResponse(let message):
            return "Adapter returned an invalid response: \(message)"
        case .adapterFailed(let message):
            return message
        }
    }
}

struct AdapterPaths {
    static var meetingSummariesToNotionRoot: URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repoAdapter = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Adapters/MeetingSummariesToNotion", isDirectory: true)

        if FileManager.default.fileExists(atPath: repoAdapter.appendingPathComponent("run.ts").path) {
            return repoAdapter
        }

        if let resourcePath = Bundle.main.resourcePath {
            let bundleAdapter = URL(fileURLWithPath: resourcePath)
                .appendingPathComponent("Adapters/MeetingSummariesToNotion", isDirectory: true)
            if FileManager.default.fileExists(atPath: bundleAdapter.appendingPathComponent("run.ts").path) {
                return bundleAdapter
            }
        }

        return repoAdapter
    }

    static var envFileURL: URL {
        meetingSummariesToNotionRoot.appendingPathComponent(".env")
    }
}

final class MeetingSummariesToNotionAdapter: SummaryAdapter {
    private let fileManager = FileManager.default
    private var activeProcess: Process?

    func cancel() {
        activeProcess?.terminate()
    }

    func generateSummary(
        transcriptPath: URL,
        summaryPath: URL,
        recordingTitle: String?,
        options: SummarizerOptions,
        skipCache: Bool = false
    ) async throws -> SummaryResult {
        let response = try await run(
            action: "summarize",
            transcriptPath: transcriptPath,
            summaryPath: summaryPath,
            recordingTitle: recordingTitle,
            options: options,
            skipCache: skipCache
        )

        guard response.success else {
            throw AdapterError.adapterFailed(response.error ?? "Summarization failed.")
        }

        let markdown = try String(contentsOf: summaryPath, encoding: .utf8)
        return SummaryResult(
            title: response.title,
            summaryPath: summaryPath,
            markdown: markdown
        )
    }

    func generateTitle(transcriptPath: URL) async throws -> String {
        let response = try await run(
            action: "title",
            transcriptPath: transcriptPath,
            summaryPath: nil,
            recordingTitle: nil,
            options: nil,
            skipCache: false
        )

        guard response.success, let title = response.title, !title.isEmpty else {
            throw AdapterError.adapterFailed(response.error ?? "Title generation failed.")
        }

        return title
    }

    private struct RunRequest: Encodable {
        let action: String
        let transcriptPath: String
        let summaryPath: String?
        let recordingTitle: String?
        let flow: String?
        let language: String?
        let skipCache: Bool
    }

    private struct RunResponse: Decodable {
        let success: Bool
        let action: String?
        let title: String?
        let summaryPath: String?
        let error: String?
    }

    private func run(
        action: String,
        transcriptPath: URL,
        summaryPath: URL?,
        recordingTitle: String?,
        options: SummarizerOptions?,
        skipCache: Bool
    ) async throws -> RunResponse {
        let settings = AppSettings.shared
        let adapterRoot = AdapterPaths.meetingSummariesToNotionRoot
        let runScript = adapterRoot.appendingPathComponent("run.ts")
        let denoPath = settings.denoBinaryPath

        guard fileManager.fileExists(atPath: denoPath) else {
            throw AdapterError.missingDeno(denoPath)
        }

        guard fileManager.fileExists(atPath: runScript.path) else {
            throw AdapterError.missingRunScript(runScript.path)
        }

        let request = RunRequest(
            action: action,
            transcriptPath: transcriptPath.path,
            summaryPath: summaryPath?.path,
            recordingTitle: recordingTitle,
            flow: options?.flow.rawValue,
            language: options?.language.rawValue,
            skipCache: skipCache
        )

        let requestData = try JSONEncoder().encode(request)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: denoPath)
        process.currentDirectoryURL = adapterRoot
        process.arguments = ["run", "--allow-all", runScript.path]
        var environment = ProcessInfo.processInfo.environment
        environment["ADAPTER_ENV_FILE"] = settings.adapterEnvPath
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        activeProcess = process
        defer { activeProcess = nil }

        try process.run()
        stdinPipe.fileHandleForWriting.write(requestData)
        try stdinPipe.fileHandleForWriting.close()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: AdapterError.adapterFailed("Adapter process was stopped."))
                    return
                }

                guard let response = Self.decodeRunResponse(from: stdoutData) else {
                    let message = [stderr, stdout]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n\n")
                    continuation.resume(throwing: AdapterError.invalidResponse(message.isEmpty ? "No JSON output." : message))
                    return
                }

                continuation.resume(returning: response)
            }
        }
    }

    private static func decodeRunResponse(from data: Data) -> RunResponse? {
        if let response = try? JSONDecoder().decode(RunResponse.self, from: data) {
            return response
        }

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard let start = text.lastIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }

        let json = String(text[start...end])
        return try? JSONDecoder().decode(RunResponse.self, from: Data(json.utf8))
    }
}
