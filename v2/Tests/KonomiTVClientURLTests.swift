import XCTest
@testable import Watchkonomi

final class KonomiTVClientURLTests: XCTestCase {

    func testSanitizeTrimsTrailingSlash() {
        XCTAssertEqual(KonomiTVClient.sanitizedBaseURL(from: "https://h:7000/")?.absoluteString, "https://h:7000")
    }

    func testSanitizeAddsHTTPS() {
        XCTAssertEqual(
            KonomiTVClient.sanitizedBaseURL(from: "100-111-2-73.local.konomi.tv:7000")?.absoluteString,
            "https://100-111-2-73.local.konomi.tv:7000"
        )
    }

    func testSanitizeRejectsInvalid() {
        XCTAssertNil(KonomiTVClient.sanitizedBaseURL(from: "ftp://h"))
        XCTAssertNil(KonomiTVClient.sanitizedBaseURL(from: ""))
        XCTAssertNil(KonomiTVClient.sanitizedBaseURL(from: "   "))
    }

    func testStreamURL() {
        let client = KonomiTVClient(baseURL: URL(string: "https://h:7000")!)
        let url = client.streamURL(displayChannelID: "gr011", quality: "1080p-60fps")
        XCTAssertEqual(url.absoluteString, "https://h:7000/api/streams/live/gr011/1080p-60fps/mpegts")
    }

    func testLogoURL() {
        let client = KonomiTVClient(baseURL: URL(string: "https://h:7000")!)
        let channel = LiveChannel(
            id: "NID32736-SID1024",
            displayChannelID: "gr011",
            channelNumber: "011",
            type: "GR",
            name: "NHK総合",
            isRadiochannel: false,
            isDisplay: true,
            programPresent: nil
        )
        XCTAssertEqual(client.logoURL(for: channel).absoluteString, "https://h:7000/api/channels/NID32736-SID1024/logo")
    }

    func testChannelsURL() {
        let client = KonomiTVClient(baseURL: URL(string: "https://h:7000")!)
        XCTAssertEqual(client.channelsURL.absoluteString, "https://h:7000/api/channels")
    }
}
