import Foundation

enum WhisperTranscriberError: LocalizedError {
    case missingBinary(String)
    case missingModel(String)
    case missingAudio(URL)
    case processFailed(String)
    case emptyOutput

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
        case .emptyOutput:
            return "Whisper finished but returned no transcript."
        }
    }
}

struct WhisperTranscriber {
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

        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-\(UUID().uuidString)")

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [
            "-m", modelURL.path,
            "-l", settings.language,
            "-otxt",
            "-np",
            "-nt",
            "-of", outputBase.path,
            audioURL.path
        ]

        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw WhisperTranscriberError.processFailed(stderr.isEmpty ? "Whisper exited with code \(process.terminationStatus)." : stderr)
        }

        let transcriptURL = URL(fileURLWithPath: outputBase.path + ".txt")
        guard FileManager.default.fileExists(atPath: transcriptURL.path) else {
            throw WhisperTranscriberError.emptyOutput
        }

        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try? FileManager.default.removeItem(at: transcriptURL)

        guard !transcript.isEmpty else {
            throw WhisperTranscriberError.emptyOutput
        }

        return transcript
    }
}
