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

enum DiarizationProgressParser {
    private static let pattern: NSRegularExpression = {
        // sherpa-onnx prints e.g. "progress 12.34%" (float, no '=')
        try! NSRegularExpression(pattern: #"progress\s+(\d+(?:\.\d+)?)\s*%"#)
    }()

    static func latestProgress(in text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: range)
        guard let last = matches.last,
              let matchRange = Range(last.range(at: 1), in: text),
              let value = Double(text[matchRange]),
              (0 ... 100).contains(value) else {
            return nil
        }
        return value / 100.0
    }
}
