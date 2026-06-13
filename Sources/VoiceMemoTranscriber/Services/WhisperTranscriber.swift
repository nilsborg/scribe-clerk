import Foundation

enum WhisperTranscriberError: LocalizedError {
    case missingBinary(String)
    case missingModel(String)
    case missingAudio(URL)
    case processFailed(String)
    case emptyOutput(details: String)

    var errorDescription: String? {
        switch self {
        case .missingBinary(let path):
            return "Whisper binary not found at \(path)."
        case .missingModel(let path):
            return "Whisper model not found at \(path)."
        case .missingAudio(let url):
            return "Audio file not found at \(url.path)."
        case .processFailed(let message):
            return message
        case .emptyOutput(let details):
            return "Whisper finished but returned no transcript.\n\n\(details)"
        }
    }
}

struct WhisperTranscriber {
    private let audioConverter = AudioConverter()

    func transcribe(audioURL: URL) async throws -> String {
        let settings = AppSettings.shared
        let binaryURL = URL(fileURLWithPath: settings.whisperBinaryPath)
        let modelURL = URL(fileURLWithPath: settings.modelPath)

        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw WhisperTranscriberError.missingBinary(settings.whisperBinaryPath)
        }

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WhisperTranscriberError.missingModel(settings.modelPath)
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw WhisperTranscriberError.missingAudio(audioURL)
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-memo-transcriber-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let preparedAudioURL = try audioConverter.whisperReadyWAV(from: audioURL, in: workDirectory)
        let outputBase = workDirectory.appendingPathComponent("transcript")

        let process = Process()
        process.executableURL = binaryURL
        process.currentDirectoryURL = workDirectory
        process.environment = ProcessInfo.processInfo.environment.merging([
            "TMPDIR": workDirectory.path
        ]) { _, new in new }
        process.arguments = [
            "-m", modelURL.path,
            "-l", settings.language,
            "-otxt",
            "-np",
            "-nt",
            "-of", outputBase.path,
            preparedAudioURL.path
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw WhisperTranscriberError.processFailed(
                stderr.isEmpty ? "Whisper exited with code \(process.terminationStatus)." : stderr
            )
        }

        let transcript = try readTranscript(
            stdout: stdout,
            outputBase: outputBase,
            preparedAudioURL: preparedAudioURL,
            workDirectory: workDirectory,
            stderr: stderr
        )

        return transcript
    }

    private func readTranscript(
        stdout: String,
        outputBase: URL,
        preparedAudioURL: URL,
        workDirectory: URL,
        stderr: String
    ) throws -> String {
        if !stdout.isEmpty {
            return stdout
        }

        let candidateURLs = [
            URL(fileURLWithPath: outputBase.path + ".txt"),
            workDirectory.appendingPathComponent(preparedAudioURL.deletingPathExtension().lastPathComponent + ".txt"),
            preparedAudioURL.deletingPathExtension().appendingPathExtension("txt")
        ]

        for url in candidateURLs {
            guard FileManager.default.fileExists(atPath: url.path),
                  let contents = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }

            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let checkedPaths = candidateURLs.map(\.path).joined(separator: "\n")
        let details = [
            stderr.isEmpty ? nil : "Whisper log:\n\(stderr)",
            "Checked output paths:\n\(checkedPaths)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")

        throw WhisperTranscriberError.emptyOutput(details: details)
    }
}
