import XCTest
@testable import WK

final class StreamMuxerTests: XCTestCase {

    private func tsRun(packetCount: Int, step: Double = 0.25) -> Data {
        var data = Data()
        for i in 0..<packetCount {
            data.append(TSTestPacketFactory.packet(pusi: true, pts: Double(i) * step))
        }
        return data
    }

    func testIngestCutsSegmentByPTS() {
        let muxer = StreamMuxer()
        muxer.beginConnection()
        muxer.ingest(tsRun(packetCount: 10))
        XCTAssertEqual(muxer.state, .onair)
        XCTAssertNotNil(muxer.segmentData(index: 0))
        XCTAssertNil(muxer.playlist())
    }

    func testPlaylistFormat() {
        let muxer = StreamMuxer()
        muxer.beginConnection()
        muxer.ingest(tsRun(packetCount: 27))
        XCTAssertTrue(muxer.isReady)
        let playlist = muxer.playlist()
        XCTAssertNotNil(playlist)
        XCTAssertTrue(playlist!.hasPrefix("#EXTM3U"))
        XCTAssertTrue(playlist!.contains("#EXT-X-MEDIA-SEQUENCE:0"))
        XCTAssertTrue(playlist!.contains("#EXTINF:2.000,"))
    }

    func testPlaylistNilBeforeReady() {
        let muxer = StreamMuxer()
        muxer.beginConnection()
        muxer.ingest(tsRun(packetCount: 9))
        XCTAssertFalse(muxer.isReady)
        XCTAssertNil(muxer.playlist())
    }

    func testWindowSlidesMediaSequence() {
        let muxer = StreamMuxer()
        muxer.beginConnection()
        muxer.ingest(tsRun(packetCount: 90))
        XCTAssertEqual(muxer.firstMediaSequence, 2)
        XCTAssertTrue(muxer.playlist()!.contains("#EXT-X-MEDIA-SEQUENCE:2"))
    }

    func testSegmentDataLookup() {
        let muxer = StreamMuxer()
        muxer.beginConnection()
        muxer.ingest(tsRun(packetCount: 90))
        XCTAssertNil(muxer.segmentData(index: 0))
        XCTAssertNotNil(muxer.segmentData(index: 2))
        XCTAssertNil(muxer.segmentData(index: 99))
    }

    func testHoldsPartialTail() {
        let muxer = StreamMuxer()
        muxer.beginConnection()
        muxer.ingest(TSTestPacketFactory.packet(pusi: true, pts: 0.0))
        muxer.ingest(TSTestPacketFactory.packet(pusi: true, pts: 0.25).prefix(94))
        XCTAssertFalse(muxer.isReady)
    }
}
