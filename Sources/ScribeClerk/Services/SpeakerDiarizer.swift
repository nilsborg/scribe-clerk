import Foundation

enum SpeakerDiarizerError: LocalizedError {
    case notConfigured(String)
    case processFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured(let hint):
            return hint
        case .processFailed(let message):
            return "Speaker diarization failed.\n\n\(message)"
        case .cancelled:
            return "Transcription was stopped."
        }
    }
}

/// Runs sherpa-onnx offline speaker diarization on a prepared WAV file and
/// returns the detected speaker turns. Language- and model-agnostic: it works
/// on the audio signal, independent of the whisper transcription.
final class SpeakerDiarizer {
    // Diarization models live alongside the whisper models.
    static let modelsDirectory = WhisperModelCatalog.modelsDirectory
        .appendingPathComponent("diarization", isDirectory: true)

    static let segmentationModelFileName = "sherpa-onnx-pyannote-segmentation-3-0.onnx"
    // VoxCeleb-trained embeddings (English/European), not the Chinese default.
    static let embeddingModelFileName = "wespeaker_en_voxceleb_resnet34_LM.onnx"

    static var segmentationModelPath: String {
        modelsDirectory.appendingPathComponent(segmentationModelFileName).path
    }

    static var embeddingModelPath: String {
        modelsDirectory.appendingPathComponent(embeddingModelFileName).path
    }

    /// Cosine-distance cut for hierarchical clustering. The sherpa-onnx default
    /// is 0.5; meetings with distinct speakers cluster better a bit higher.
    /// Raise it if distinct speakers get merged, lower it if one person is split.
    static let clusterThreshold = 0.7

    /// True when the binary and both ONNX models are present.
    static var isConfigured: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: AppSettings.shared.diarizationBinaryPath)
            && fm.fileExists(atPath: segmentationModelPath)
            && fm.fileExists(atPath: embeddingModelPath)
    }

    static var setupHint: String {
        "Speaker detection needs sherpa-onnx. Install the binary (set its path in Settings) and place \(segmentationModelFileName) and \(embeddingModelFileName) in \(modelsDirectory.path). See the README for download links."
    }

    private var activeProcess: Process?

    func cancel() {
        activeProcess?.terminate()
    }

    func diarize(
        audioURL: URL,
        speakerCount: Int? = nil,
        onLog: (@MainActor (String) -> Void)? = nil
    ) async throws -> [SpeakerTurn] {
        try Task.checkCancellation()

        let fm = FileManager.default
        let binaryPath = AppSettings.shared.diarizationBinaryPath

        guard fm.fileExists(atPath: binaryPath),
              fm.fileExists(atPath: Self.segmentationModelPath),
              fm.fileExists(atPath: Self.embeddingModelPath) else {
            throw SpeakerDiarizerError.notConfigured(Self.setupHint)
        }

        // With a known speaker count, pin it (more accurate); otherwise auto-detect
        // by cutting the clustering at a distance threshold.
        let clusteringArg: String
        if let speakerCount, speakerCount > 0 {
            clusteringArg = "--clustering.num-clusters=\(speakerCount)"
        } else {
            clusteringArg = "--clustering.cluster-threshold=\(Self.clusterThreshold)"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "--segmentation.pyannote-model=\(Self.segmentationModelPath)",
            "--embedding.model=\(Self.embeddingModelPath)",
            clusteringArg,
            // There is no global --num-threads; it is per-model.
            "--segmentation.num-threads=2",
            "--embedding.num-threads=2",
            audioURL.path
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let onLog {
            Task { @MainActor in onLog("[diarize] Identifying speakers…\n") }
        }

        // Stream stderr live so its `progress N%` lines drive the progress bar.
        let stderrBuffer = LogBuffer()
        let stderrHandle = stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            stderrBuffer.append(chunk)
            if let onLog {
                Task { @MainActor in onLog(chunk) }
            }
        }

        activeProcess = process
        defer { activeProcess = nil }

        try process.run()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { process in
                if Task.isCancelled || process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: SpeakerDiarizerError.cancelled)
                    return
                }
                continuation.resume()
            }
        }

        try Task.checkCancellation()

        stderrHandle.readabilityHandler = nil
        if let remaining = String(data: stderrHandle.readDataToEndOfFile(), encoding: .utf8) {
            stderrBuffer.append(remaining)
        }
        let stderr = stderrBuffer.text
        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            if process.terminationReason == .uncaughtSignal {
                throw SpeakerDiarizerError.cancelled
            }
            throw SpeakerDiarizerError.processFailed(
                stderr.isEmpty ? "sherpa-onnx exited with code \(process.terminationStatus)." : stderr
            )
        }

        // Result lines print only to stdout, as `%.3f -- %.3f speaker_%02d`,
        // amid a config dump and a "Started" line that parseTurns ignores.
        let turns = Self.parseTurns(stdout)
        guard !turns.isEmpty else {
            throw SpeakerDiarizerError.processFailed(
                "No speaker segments were detected.\n\n\(stderr)"
            )
        }
        return turns
    }

    /// Parses lines of the exact form `0.031 -- 2.031 speaker_00` (seconds),
    /// skipping the config dump, `Started`, and any other output.
    static func parseTurns(_ output: String) -> [SpeakerTurn] {
        var turns: [SpeakerTurn] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // Expect exactly: <start> "--" <end> speaker_<NN>
            guard parts.count == 4,
                  parts[1] == "--",
                  parts[3].hasPrefix("speaker_"),
                  let start = Double(parts[0]),
                  let end = Double(parts[2]) else {
                continue
            }
            turns.append(SpeakerTurn(start: start, end: end, speaker: parts[3]))
        }
        return turns.sorted { $0.start < $1.start }
    }
}

/// Thread-safe string accumulator for a pipe's readability handler, which runs
/// on a background queue.
private final class LogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func append(_ chunk: String) {
        lock.lock(); defer { lock.unlock() }
        value += chunk
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
