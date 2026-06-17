import AVFoundation
import Foundation

enum AudioDuration {
    static func seconds(for url: URL) -> TimeInterval? {
        secondsFromAsset(url) ?? secondsFromAudioFile(url)
    }

    static func formatted(for url: URL) -> String? {
        formatted(seconds: seconds(for: url))
    }

    static func formatted(seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private static func secondsFromAsset(_ url: URL) -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        var seconds: TimeInterval?
        let group = DispatchGroup()
        group.enter()
        Task.detached {
            defer { group.leave() }
            guard let duration = try? await asset.load(.duration) else { return }
            let value = CMTimeGetSeconds(duration)
            guard value.isFinite, value > 0 else { return }
            seconds = value
        }
        group.wait()
        return seconds
    }

    private static func secondsFromAudioFile(_ url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        let seconds = Double(file.length) / sampleRate
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }
}
