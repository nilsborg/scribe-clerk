import XCTest
@testable import ScribeClerk

final class WhisperConfigurationTests: XCTestCase {
    func testConfiguredModelWinsWhenInstalled() {
        let medium = "/models/ggml-medium.bin"
        let turbo = "/models/ggml-large-v3-turbo.bin"

        XCTAssertEqual(
            WhisperModelCatalog.resolvedDefaultModelPath(
                configuredPath: medium,
                availablePaths: [turbo, medium]
            ),
            medium
        )
    }

    func testTurboIsFallbackWhenConfiguredModelIsMissing() {
        let turbo = "/models/ggml-large-v3-turbo.bin"

        XCTAssertEqual(
            WhisperModelCatalog.resolvedDefaultModelPath(
                configuredPath: "/models/missing.bin",
                availablePaths: ["/models/ggml-small.bin", turbo]
            ),
            turbo
        )
    }

    func testWhisperProgressIsClampedToOne() {
        XCTAssertEqual(
            WhisperProgressParser.latestProgress(
                in: "whisper_print_progress_callback: progress = 253%"
            ),
            1
        )
    }

    func testDiarizationProgressParsesDecimals() {
        XCTAssertEqual(
            DiarizationProgressParser.latestProgress(in: "progress 25.50%"),
            0.255
        )
    }
}
