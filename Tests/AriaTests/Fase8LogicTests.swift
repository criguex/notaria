import XCTest
@testable import aria_capture

final class Fase8LogicTests: XCTestCase {

    private func toneFixture() -> [Float] {
        let sampleRate = 16_000
        var samples = [Float](repeating: 0, count: sampleRate * 10)
        for index in (2 * sampleRate)..<(4 * sampleRate) {
            samples[index] = sinf(Float(index) * 0.1) * 0.3
        }
        return samples
    }

    private func missingModelURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aria-silero-missing-\(UUID().uuidString).bin")
    }

    func testSileroModelIsUnavailableWithoutFile() {
        let missing = missingModelURL()
        XCTAssertFalse(SileroModel.isAvailable(at: missing))
        XCTAssertEqual(VADFactory.backendName(modelAvailable: SileroModel.isAvailable(at: missing)), "energy")
        XCTAssertEqual(VADFactory.backendName(modelAvailable: true), "silero")
    }

    func testEnergyVADMatchesStaticLogic() {
        let samples = toneFixture()
        let viaStatic = ChunkedTranscriber.voicedRegions(in: samples, options: .default, sampleRate: 16_000)
        let viaProtocol = EnergyVAD().voicedRegions(in: samples, sampleRate: 16_000)
        XCTAssertEqual(viaStatic.map { $0.lowerBound }, viaProtocol.map { $0.lowerBound })
        XCTAssertEqual(viaStatic.map { $0.upperBound }, viaProtocol.map { $0.upperBound })
    }

    func testSileroVADInitFailsWhenModelFileMissing() {
        let missingPath = NSTemporaryDirectory() + "no-existe-\(UUID().uuidString).bin"
        XCTAssertNil(SileroVAD(modelPath: missingPath))
    }

    func testVADFactoryPrefersEnergyWhenModelAbsent() {
        let vad = VADFactory.preferred(modelURL: missingModelURL())
        XCTAssertTrue(vad is EnergyVAD)
    }

    func testRequiredPermissionsSkipsScreenRecordingInDictationMode() {
        XCTAssertFalse(RequiredPermissions.needsScreenRecording(dictationOnly: true))
        XCTAssertTrue(RequiredPermissions.needsScreenRecording(dictationOnly: false))
    }

    func testBrowserMeetingDetectorProviderMatchesKnownDomains() {
        XCTAssertEqual(BrowserMeetingDetector.provider(forURL: "https://meet.google.com/abc-defg-hij"), "Meet")
        XCTAssertEqual(BrowserMeetingDetector.provider(forURL: "https://us05web.zoom.us/j/123456"), "Zoom")
        XCTAssertEqual(BrowserMeetingDetector.provider(forURL: "https://teams.microsoft.com/l/meetup-join/x"), "Teams")
        XCTAssertNil(BrowserMeetingDetector.provider(forURL: "https://example.com/not-a-call"))
        XCTAssertNil(BrowserMeetingDetector.provider(forURL: ""))
    }

    func testBrowserMeetingDetectorLabelsDeduplicatesAndSortsPerBrowser() {
        let labels = BrowserMeetingDetector.labels(
            forTabURLs: [
                "https://meet.google.com/abc-defg-hij",
                "https://mail.google.com/mail/u/0",
                "https://zoom.us/j/999",
                "https://meet.google.com/abc-defg-hij"
            ],
            browserName: "Google Chrome"
        )
        XCTAssertEqual(labels, ["Meet (Google Chrome)", "Zoom (Google Chrome)"])
    }

    func testBrowserMeetingDetectorLabelsEmptyWhenNoCallTabs() {
        let labels = BrowserMeetingDetector.labels(
            forTabURLs: ["https://example.com", "https://github.com"],
            browserName: "Safari"
        )
        XCTAssertTrue(labels.isEmpty)
    }
}
