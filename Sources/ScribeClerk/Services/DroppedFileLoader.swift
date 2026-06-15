import Foundation
import UniformTypeIdentifiers

enum AudioDropTypes {
    static let accepted: [UTType] = [
        .fileURL,
        .url,
        .audio,
        .mpeg4Audio,
        .data,
        .item
    ]
}

enum DroppedFileLoader {
    static func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []

        for provider in providers {
            if let url = await loadURL(from: provider) {
                urls.append(url)
            }
        }

        return urls
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        let typeIdentifiers = provider.registeredTypeIdentifiers + [
            UTType.fileURL.identifier,
            UTType.url.identifier,
            UTType.mpeg4Audio.identifier,
            UTType.audio.identifier,
            UTType.data.identifier,
            "public.mpeg-4-audio"
        ]

        for typeId in Set(typeIdentifiers) {
            guard provider.hasItemConformingToTypeIdentifier(typeId) else { continue }

            if let url = await loadFileRepresentation(from: provider, typeId: typeId) {
                return url
            }

            if let url = await loadItemURL(from: provider, typeId: typeId) {
                return url
            }
        }

        return nil
    }

    private static func loadFileRepresentation(
        from provider: NSItemProvider,
        typeId: String
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: AudioInbox.persist(url))
            }
        }
    }

    private static func loadItemURL(
        from provider: NSItemProvider,
        typeId: String
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }

                if let string = item as? String {
                    if let url = URL(string: string), url.isFileURL {
                        continuation.resume(returning: url)
                        return
                    }

                    if string.hasPrefix("/") {
                        continuation.resume(returning: URL(fileURLWithPath: string))
                        return
                    }
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
