import Foundation
import UniformTypeIdentifiers

enum TranscriptionFileFilter {
    static let extensions = ["vtt", "srt", "txt"]

    static let acceptedTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text]
        for ext in extensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return Array(Set(types))
    }()

    static func filter(_ urls: [URL]) -> [URL] {
        urls.filter(isTranscriptionFile)
    }

    static func isTranscriptionFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard !AudioFileFilter.isAudioFile(url) else { return false }

        let ext = url.pathExtension.lowercased()
        if extensions.contains(ext) {
            return true
        }

        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .text) {
            return true
        }

        return false
    }
}
