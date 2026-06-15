import Foundation
import UniformTypeIdentifiers

enum AudioFileFilter {
    static let extensions = [
        "m4a", "mp3", "wav", "flac", "ogg", "aac", "aiff", "aif", "caf", "wma", "mp4", "webm"
    ]

    static let acceptedTypes: [UTType] = {
        var types: [UTType] = [.audio, .mpeg4Audio, .wav, .mp3, .aiff]
        for ext in extensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return Array(Set(types))
    }()

    static func filter(_ urls: [URL]) -> [URL] {
        urls.filter(isAudioFile)
    }

    static func isAudioFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        if extensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        if let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .audio) {
            return true
        }

        return false
    }
}
