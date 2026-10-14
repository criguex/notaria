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

    func testSileroModelIsUnavailableWithoutFile() {
        XCTAssertFalse(SileroModel.isAvailable)
        XCTAssertEqual(VADFactory.backendName(), "energy")
        XCTAssertEqual(VADFactory.backendName(modelAvailable: true), "silero")
    }

    func testEnergyVADMatchesStaticLogic() {
        let samples = toneFixture()
        let viaStatic = ChunkedTranscriber.voicedRegions(in: samples, options: .default, sampleRate: 16_000)
        let viaProtocol = EnergyVAD().voicedRegions(in: samples, sampleRate: 16_000)
        XCTAssertEqual(viaStatic.map { $0.lowerBound }, viaProtocol.map { $0.lowerBound })
        XCTAssertEqual(viaStatic.map { $0.upperBound }, viaProtocol.map { $0.upperBound })
    }

    func testSileroVADFallsBackToEnergyWhenModelMissing() {
        let samples = toneFixture()
        let energy = EnergyVAD().voicedRegions(in: samples, sampleRate: 16_000)
        let silero = SileroVAD().voicedRegions(in: samples, sampleRate: 16_000)
        XCTAssertEqual(energy.map { $0.lowerBound }, silero.map { $0.lowerBound })
        XCTAssertEqual(energy.map { $0.upperBound }, silero.map { $0.upperBound })
    }

    func testVADFactoryPrefersEnergyWhenModelAbsent() {
        let vad = VADFactory.preferred()
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
