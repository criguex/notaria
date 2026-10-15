import XCTest
@testable import aria_capture

final class MeetingJoinLogicTests: XCTestCase {

    // MARK: - MeetingPlatform.detect

    func testPlatformDetectRecognizesKnownDomains() {
        XCTAssertEqual(MeetingPlatform.detect(fromURL: "https://meet.google.com/abc-defg-hij"), .meet)
        XCTAssertEqual(MeetingPlatform.detect(fromURL: "https://us05web.zoom.us/j/123456"), .zoom)
        XCTAssertEqual(MeetingPlatform.detect(fromURL: "https://teams.microsoft.com/l/meetup-join/x"), .teams)
        XCTAssertNil(MeetingPlatform.detect(fromURL: "https://example.com/not-a-call"))
        XCTAssertNil(MeetingPlatform.detect(fromURL: ""))
    }

    // MARK: - MeetingJoinLink.resolve

    func testResolveReturnsNilForEmptyLink() {
        XCTAssertNil(MeetingJoinLink.resolve(videoLink: "", nativeAppInstalled: true))
    }

    func testResolveKeepsHTTPSForMeetRegardlessOfNativeApp() {
        let link = "https://meet.google.com/aaa-bbbb-ccc"
        XCTAssertEqual(MeetingJoinLink.resolve(videoLink: link, nativeAppInstalled: false)?.absoluteString, link)
        XCTAssertEqual(MeetingJoinLink.resolve(videoLink: link, nativeAppInstalled: true)?.absoluteString, link)
    }

    func testResolveKeepsHTTPSForWebexRegardlessOfNativeApp() {
        let link = "https://acme.webex.com/meet/jdoe"
        XCTAssertEqual(MeetingJoinLink.resolve(videoLink: link, nativeAppInstalled: true)?.absoluteString, link)
    }

    func testResolveFallsBackToHTTPSWhenNativeAppNotInstalled() {
        let teams = "https://teams.microsoft.com/l/meetup-join/xyz?context=abc"
        XCTAssertEqual(MeetingJoinLink.resolve(videoLink: teams, nativeAppInstalled: false)?.absoluteString, teams)
        let zoom = "https://us05web.zoom.us/j/123456789?pwd=abcDEF"
        XCTAssertEqual(MeetingJoinLink.resolve(videoLink: zoom, nativeAppInstalled: false)?.absoluteString, zoom)
    }

    func testResolvePrefersTeamsNativeSchemeWhenInstalled() {
        let teams = "https://teams.microsoft.com/l/meetup-join/xyz?context=abc"
        let resolved = MeetingJoinLink.resolve(videoLink: teams, nativeAppInstalled: true)
        XCTAssertEqual(resolved?.absoluteString, "msteams:/l/meetup-join/xyz?context=abc")
    }

    func testResolvePrefersTeamsLiveNativeSchemeWhenInstalled() {
        let teams = "https://teams.live.com/meet/999"
        let resolved = MeetingJoinLink.resolve(videoLink: teams, nativeAppInstalled: true)
        XCTAssertEqual(resolved?.absoluteString, "msteams:/meet/999")
    }

    func testResolvePrefersZoomNativeSchemeWhenInstalled() {
        let zoom = "https://us05web.zoom.us/j/123456789?pwd=abcDEF"
        let resolved = MeetingJoinLink.resolve(videoLink: zoom, nativeAppInstalled: true)
        XCTAssertEqual(resolved?.scheme, "zoommtg")
        XCTAssertEqual(resolved?.host, "zoom.us")
        XCTAssertEqual(resolved?.path, "/join")
        let query = resolved?.query ?? ""
        XCTAssertTrue(query.contains("confno=123456789"))
        XCTAssertTrue(query.contains("pwd=abcDEF"))
    }

    func testResolveZoomNativeWithoutPasswordOmitsPwdParam() {
        let zoom = "https://zoom.us/j/999"
        let resolved = MeetingJoinLink.resolve(videoLink: zoom, nativeAppInstalled: true)
        XCTAssertEqual(resolved?.query, "action=join&confno=999")
    }

    func testResolveZoomPersonalLinkUsesMyPath() {
        let zoom = "https://zoom.us/my/jdoe"
        let resolved = MeetingJoinLink.resolve(videoLink: zoom, nativeAppInstalled: true)
        XCTAssertEqual(resolved?.query, "action=join&confno=jdoe")
    }

    func testResolveZoomWithoutRecognizableMeetingIdFallsBackToHTTPS() {
        let zoom = "https://zoom.us/webinar/register"
        let resolved = MeetingJoinLink.resolve(videoLink: zoom, nativeAppInstalled: true)
        XCTAssertEqual(resolved?.absoluteString, zoom)
    }

    // MARK: - MeetingPromptLayout.decide

    func testPromptLayoutNoLinkWhenMissingVideoLink() {
        XCTAssertEqual(MeetingPromptLayout.decide(videoLink: nil, nativeAppInstalled: false), .noLink)
        XCTAssertEqual(MeetingPromptLayout.decide(videoLink: "", nativeAppInstalled: false), .noLink)
    }

    func testPromptLayoutWithLinkResolvesURL() {
        let link = "https://meet.google.com/aaa-bbbb-ccc"
        XCTAssertEqual(
            MeetingPromptLayout.decide(videoLink: link, nativeAppInstalled: false),
            .withLink(joinURL: URL(string: link)!)
        )
    }
}
