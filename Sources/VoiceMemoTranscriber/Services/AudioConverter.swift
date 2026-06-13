import Foundation

enum AudioConverterError: LocalizedError {
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let message):
            return message
        }
    }
}

struct AudioConverter {
    /// Voice Memos recordings are `.m4a`, while whisper-cli reliably supports wav/flac/mp3/ogg.
    /// Convert to 16 kHz mono WAV using the built-in `afconvert` tool.
    func whisperReadyWAV(from sourceURL: URL, in directory: URL) throws -> URL {
        let lowercasedExtension = sourceURL.pathExtension.lowercased()
        if lowercasedExtension == "wav" {
            return sourceURL
        }

        let outputURL = directory.appendingPathComponent("\(UUID().uuidString).wav")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
            sourceURL.path,
            outputURL.path
        ]

        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AudioConverterError.conversionFailed(
                stderr.isEmpty
                    ? "Could not convert \(sourceURL.lastPathComponent) to WAV (exit code \(process.terminationStatus))."
                    : stderr
            )
        }

        return outputURL
    }
}
