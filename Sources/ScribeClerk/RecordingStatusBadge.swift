import SwiftUI

struct StatusBadge: View {
    let recording: RecordingRecord
    @ObservedObject var appState: AppState

    var body: some View {
        let descriptor = RecordingStatusDescriptor(recording: recording, appState: appState)
        Label(descriptor.label, systemImage: descriptor.icon)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .foregroundStyle(descriptor.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(descriptor.color.opacity(0.12), in: Capsule())
    }
}

struct RecordingStatusDescriptor {
    let label: String
    let icon: String
    let color: Color
    let isActive: Bool

    @MainActor
    init(recording: RecordingRecord, appState: AppState? = nil) {
        if let appState, appState.activePublishRecordingID == recording.id {
            label = "Publishing…"
            icon = "paperplane.circle"
            color = .accentColor
            isActive = true
            return
        }

        if let appState, appState.activeSummaryRecordingID == recording.id {
            label = "Summarizing…"
            icon = "text.append"
            color = .accentColor
            isActive = true
            return
        }

        if recording.summaryVariants.contains(where: { $0.status == .publishing }) {
            label = "Publishing…"
            icon = "paperplane.circle"
            color = .accentColor
            isActive = true
            return
        }

        if recording.summaryVariants.contains(where: { $0.status == .generating }) {
            label = "Summarizing…"
            icon = "text.append"
            color = .accentColor
            isActive = true
            return
        }

        if recording.summaryVariants.contains(where: { $0.status == .queued }) {
            label = "Queued"
            icon = "clock"
            color = .accentColor
            isActive = false
            return
        }

        if let published = recording.summaryVariants.first(where: { $0.status == .published }) {
            label = "Published · \(published.options.flow.label)"
            icon = "paperplane.circle.fill"
            color = .green
            isActive = false
            return
        }

        if recording.summaryVariants.contains(where: { $0.status == .ready || $0.status == .stale }) {
            label = "Summarized"
            icon = "text.append"
            color = .blue
            isActive = false
            return
        }

        switch recording.transcriptionStatus {
        case .completed:
            label = "Transcribed"
            icon = "checkmark.circle.fill"
            color = .green
            isActive = false
        case .failed:
            label = "Failed"
            icon = "exclamationmark.triangle.fill"
            color = .red
            isActive = false
        case .inProgress:
            if let appState,
               appState.activeTranscriptionRecordingID == recording.id,
               let progress = appState.transcriptionProgress {
                label = "Transcribing… \(Int((progress * 100).rounded()))%"
            } else {
                label = "Transcribing…"
            }
            icon = "waveform"
            color = .accentColor
            isActive = true
        case .queued:
            label = "Queued"
            icon = "clock"
            color = .accentColor
            isActive = false
        case .notStarted:
            label = recording.source.label
            icon = "tray.and.arrow.down"
            color = .secondary
            isActive = false
        }
    }
}
