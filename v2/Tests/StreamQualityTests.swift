import XCTest
@testable import WK

final class StreamQualityTests: XCTestCase {
    func testQualityRawValuesMatchAPI() {
        XCTAssertEqual(
            StreamQuality.allCases.map(\.rawValue),
            ["240p", "360p", "480p", "540p", "720p", "810p", "1080p", "1080p-60fps"]
        )
    }

    func testQualityLabel() {
        XCTAssertEqual(StreamQuality(rawValue: "1080p-60fps")!.label, "1080p (60fps)")
        XCTAssertEqual(StreamQuality(rawValue: "240p")!.label, "240p")
    }
}
