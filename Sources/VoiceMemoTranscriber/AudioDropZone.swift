import SwiftUI
import UniformTypeIdentifiers

struct AudioDropZone: View {
    var title: String = "Drop audio files here"
    var subtitle: String = "Drag recordings from Voice Memos, or any audio file"
    var inset: CGFloat = 32
    var onFiles: ([URL]) -> Void

    @State private var isTargeted = false
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "waveform.circle")
                .font(.system(size: 44))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .symbolEffect(.bounce, value: isTargeted)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Choose Files…") {
                showImporter = true
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.45),
                    style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 2, dash: isTargeted ? [] : [10, 7])
                )
        }
        .padding(inset)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .onDrop(of: AudioDropTypes.accepted, isTargeted: $isTargeted, perform: handleDrop)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: AudioFileFilter.acceptedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let audioFiles = AudioFileFilter.filter(urls)
                if !audioFiles.isEmpty {
                    onFiles(audioFiles)
                }
            case .failure:
                break
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            let urls = await DroppedFileLoader.loadURLs(from: providers)
            let audioFiles = AudioFileFilter.filter(urls)
            guard !audioFiles.isEmpty else { return }

            await MainActor.run {
                onFiles(audioFiles)
            }
        }

        return true
    }
}
