import UniformTypeIdentifiers

enum ImportFileTypes {
    static let accepted: [UTType] = Array(
        Set(AudioFileFilter.acceptedTypes + TranscriptionFileFilter.acceptedTypes)
    )
}
