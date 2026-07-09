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

        return try convertToSixteenKMonoWAV(from: sourceURL, in: directory)
    }

    /// Produces a 16 kHz mono WAV with a *canonical* PCM header (16-byte `fmt `
    /// chunk, format tag 1). sherpa-onnx diarization requires this exact layout —
    /// it hard-errors on afconvert's default WAVE_FORMAT_EXTENSIBLE header and does
    /// not resample — so we rewrite the header after converting.
    func sixteenKMonoWAV(from sourceURL: URL, in directory: URL) throws -> URL {
        let converted = try convertToSixteenKMonoWAV(from: sourceURL, in: directory)
        let canonicalURL = directory.appendingPathComponent("\(UUID().uuidString)-pcm.wav")
        try Self.writeCanonicalPCMWAV(from: converted, to: canonicalURL)
        return canonicalURL
    }

    /// Re-wraps the PCM `data` chunk of a WAV file in a canonical 44-byte header.
    /// The sample bytes are copied unchanged; only the container header differs.
    static func writeCanonicalPCMWAV(from source: URL, to destination: URL) throws {
        let raw = try Data(contentsOf: source)
        guard raw.count >= 44,
              raw[raw.startIndex ..< raw.startIndex + 4].elementsEqual(Array("RIFF".utf8)),
              raw[raw.startIndex + 8 ..< raw.startIndex + 12].elementsEqual(Array("WAVE".utf8)) else {
            throw AudioConverterError.conversionFailed("Not a RIFF/WAVE file: \(source.lastPathComponent)")
        }

        func u16(_ offset: Int) -> UInt16 {
            UInt16(raw[raw.startIndex + offset]) | (UInt16(raw[raw.startIndex + offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> Int {
            Int(raw[raw.startIndex + offset]) | (Int(raw[raw.startIndex + offset + 1]) << 8)
                | (Int(raw[raw.startIndex + offset + 2]) << 16) | (Int(raw[raw.startIndex + offset + 3]) << 24)
        }

        var channels: UInt16 = 1
        var sampleRate = 16000
        var bitsPerSample: UInt16 = 16
        var dataChunk: Data?

        var pos = 12
        while pos + 8 <= raw.count {
            let id = raw[raw.startIndex + pos ..< raw.startIndex + pos + 4]
            let size = u32(pos + 4)
            let bodyStart = pos + 8
            guard size >= 0, bodyStart + size <= raw.count else { break }
            if id.elementsEqual(Array("fmt ".utf8)), size >= 16 {
                channels = u16(bodyStart + 2)
                sampleRate = u32(bodyStart + 4)
                bitsPerSample = u16(bodyStart + 14)
            } else if id.elementsEqual(Array("data".utf8)) {
                dataChunk = raw.subdata(in: raw.startIndex + bodyStart ..< raw.startIndex + bodyStart + size)
            }
            pos = bodyStart + size + (size & 1) // chunks are word-aligned
        }

        guard let data = dataChunk else {
            throw AudioConverterError.conversionFailed("No PCM data chunk in \(source.lastPathComponent)")
        }

        var out = Data()
        func put32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        func put16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        let byteRate = sampleRate * Int(channels) * Int(bitsPerSample) / 8
        let blockAlign = Int(channels) * Int(bitsPerSample) / 8

        out.append(contentsOf: Array("RIFF".utf8)); put32(36 + data.count); out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8)); put32(16); put16(1); put16(Int(channels))
        put32(sampleRate); put32(byteRate); put16(blockAlign); put16(Int(bitsPerSample))
        out.append(contentsOf: Array("data".utf8)); put32(data.count); out.append(data)

        try out.write(to: destination)
    }

    private func convertToSixteenKMonoWAV(from sourceURL: URL, in directory: URL) throws -> URL {
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
