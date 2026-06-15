import Foundation

struct TranscriptionLanguageOption: Identifiable, Hashable {
    let code: String
    let label: String

    var id: String { code }

    static let options: [TranscriptionLanguageOption] = [
        .init(code: "auto", label: "Auto-detect"),
        .init(code: "en", label: "English"),
        .init(code: "de", label: "German"),
        .init(code: "fr", label: "French"),
        .init(code: "es", label: "Spanish"),
        .init(code: "it", label: "Italian"),
        .init(code: "nl", label: "Dutch"),
        .init(code: "pt", label: "Portuguese")
    ]

    static let quickPickCodes = ["auto", "en", "de"]

    static func label(for code: String) -> String {
        options.first { $0.code == code }?.label ?? code
    }
}
