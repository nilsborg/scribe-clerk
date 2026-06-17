import Foundation

enum WhisperProgressParser {
    private static let pattern: NSRegularExpression = {
        // whisper_print_progress_callback: progress =  45%
        try! NSRegularExpression(pattern: #"progress\s*=\s*(\d+)\s*%"#)
    }()

    static func latestProgress(in text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: range)
        guard let last = matches.last,
              let matchRange = Range(last.range(at: 1), in: text),
              let value = Int(text[matchRange]),
              (0 ... 100).contains(value) else {
            return nil
        }
        return Double(value) / 100.0
    }
}
