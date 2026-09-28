import Foundation

/// Which stage of the transcription pipeline is currently running.
enum TranscriptionPhase {
    case transcribing
    case diarizing
}

enum WhisperTranscriberError: LocalizedError {
    case missingBinary(String)
    case missingModel(String)
    case missingAudio(URL)
    case processFailed(String)
    case emptyOutput(details: String)
    case cancelled

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
        case .cancelled:
            return "Transcription was stopped."
        }
    }
}

final class WhisperTranscriber {
    private let audioConverter = AudioConverter()
    private let speakerDiarizer = SpeakerDiarizer()
    private var activeProcess: Process?

    func cancel() {
        if activeProcess?.isRunning == true {
            activeProcess?.terminate()
        }
        speakerDiarizer.cancel()
    }

    func transcribe(
        audioURL: URL,
        options: TranscriptionOptions,
        onLog: (@MainActor (String) -> Void)? = nil,
        onPhase: (@MainActor (TranscriptionPhase) -> Void)? = nil
    ) async throws -> TranscriptRecord {
        try Task.checkCancellation()

        let settings = AppSettings.shared
        let binaryURL = URL(fileURLWithPath: settings.whisperBinaryPath)
        let modelURL = URL(fileURLWithPath: options.modelPath)

        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw WhisperTranscriberError.missingBinary(settings.whisperBinaryPath)
        }

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WhisperTranscriberError.missingModel(options.modelPath)
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw WhisperTranscriberError.missingAudio(audioURL)
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-clerk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let preparedAudioURL = try audioConverter.transcriptionReadyWAV(from: audioURL, in: workDirectory)
        let outputBase = workDirectory.appendingPathComponent("transcript")

        let diarizationTask: Task<[SpeakerTurn], Error>? = options.identifySpeakers
            ? Task {
                try await speakerDiarizer.diarize(
                    audioURL: preparedAudioURL,
                    speakerCount: options.speakerCount,
                    onLog: onLog
                )
            }
            : nil

        let process = Process()
        process.executableURL = binaryURL
        process.currentDirectoryURL = workDirectory
        process.environment = ProcessInfo.processInfo.environment.merging([
            "TMPDIR": workDirectory.path
        ]) { _, new in new }
        var arguments = [
            "-m", modelURL.path,
            "-l", options.language,
            "-np",
            "-pp",
            "-of", outputBase.path
        ]
        if options.identifySpeakers {
            // Diarization needs per-segment timestamps, so emit JSON and keep timestamps.
            arguments += ["-oj"]
        } else {
            arguments += ["-otxt", "-nt"]
        }
        if settings.voiceActivityDetectionEnabled, WhisperVAD.isConfigured {
            arguments += ["--vad", "--vad-model", WhisperVAD.modelURL.path]
        }
        if let prompt = settings.transcriptionPrompt {
            arguments += ["--prompt", prompt, "--carry-initial-prompt"]
        }
        arguments.append(preparedAudioURL.path)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let finishStdout = attachStream(to: stdoutPipe.fileHandleForReading, onLog: onLog)
        let finishStderr = attachStream(to: stderrPipe.fileHandleForReading, prefix: "[stderr] ", onLog: onLog)

        activeProcess = process
        defer {
            activeProcess = nil
            _ = finishStdout()
            _ = finishStderr()
        }

        do {
            if settings.voiceActivityDetectionEnabled, !WhisperVAD.isConfigured, let onLog {
                Task { @MainActor in
                    onLog("[vad] \(WhisperVAD.setupHint) Continuing without VAD.\n")
                }
            }

            try Task.checkCancellation()
            try process.run()
            if Task.isCancelled {
                process.terminate()
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { process in
                    if Task.isCancelled || process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: WhisperTranscriberError.cancelled)
                        return
                    }
                    continuation.resume()
                }
            }

            try Task.checkCancellation()

            let stdout = finishStdout().trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = finishStderr().trimmingCharacters(in: .whitespacesAndNewlines)

            guard process.terminationStatus == 0 else {
                if process.terminationReason == .uncaughtSignal {
                    throw WhisperTranscriberError.cancelled
                }
                throw WhisperTranscriberError.processFailed(
                    stderr.isEmpty ? "Whisper exited with code \(process.terminationStatus)." : stderr
                )
            }

            let text: String
            if let diarizationTask {
                let segments = try TranscriptSegment.parseWhisperJSON(
                    at: URL(fileURLWithPath: outputBase.path + ".json")
                )
                if let onPhase {
                    Task { @MainActor in onPhase(.diarizing) }
                }
                let speakerTurns = try await diarizationTask.value
                text = SpeakerLabeler.label(segments: segments, with: speakerTurns)
            } else {
                text = try readTranscript(
                    stdout: stdout,
                    outputBase: outputBase,
                    preparedAudioURL: preparedAudioURL,
                    workDirectory: workDirectory,
                    stderr: stderr
                )
            }

            return TranscriptRecord(
                text: text,
                language: options.language,
                modelPath: options.modelPath,
                createdAt: Date(),
                sourceURLString: nil,
                sourceName: nil
            )
        } catch {
            diarizationTask?.cancel()
            speakerDiarizer.cancel()
            if let diarizationTask {
                _ = try? await diarizationTask.value
            }
            throw error
        }
    }

    private func attachStream(
        to handle: FileHandle,
        prefix: String = "",
        onLog: (@MainActor (String) -> Void)?
    ) -> () -> String {
        var accumulated = ""

        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty,
                  let chunk = String(data: data, encoding: .utf8) else {
                return
            }

            accumulated += chunk
            guard let onLog else { return }
            let output = prefix.isEmpty ? chunk : chunk.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line in
                    line.isEmpty ? prefix : "\(prefix)\(line)"
                }
                .joined(separator: "\n")
            Task { @MainActor in
                onLog(output.hasSuffix("\n") ? output : output + "\n")
            }
        }

        return {
            handle.readabilityHandler = nil
            let remainingData = handle.readDataToEndOfFile()
            if let remaining = String(data: remainingData, encoding: .utf8), !remaining.isEmpty {
                accumulated += remaining
                if let onLog {
                    let output = prefix.isEmpty ? remaining : remaining.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { line in
                            line.isEmpty ? prefix : "\(prefix)\(line)"
                        }
                        .joined(separator: "\n")
                    Task { @MainActor in
                        onLog(output.hasSuffix("\n") ? output : output + "\n")
                    }
                }
            }
            return accumulated
        }
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
