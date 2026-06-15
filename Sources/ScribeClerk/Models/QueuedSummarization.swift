import Foundation

struct QueuedSummarization: Equatable {
    let jobID: String
    let options: SummarizerOptions
}

enum SummarizerJobState: Equatable {
    case none
    case queued(position: Int)
    case inProgress
}
