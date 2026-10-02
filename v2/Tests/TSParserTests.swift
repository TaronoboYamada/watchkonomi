import XCTest
@testable import Watchkonomi

final class TSParserTests: XCTestCase {

    func testExtractPTSFromPESPacket() {
        let packet = TSTestPacketFactory.packet(pusi: true, pts: 123.456)
        XCTAssertEqual(TSParser.extractPTS(from: packet) ?? -1, 123.456, accuracy: 0.001)
    }

    func testExtractPTSNilForNonPES() {
        XCTAssertNil(TSParser.extractPTS(from: TSTestPacketFactory.packet(pusi: false, pts: nil)))
        XCTAssertNil(TSParser.extractPTS(from: TSTestPacketFactory.packet(pusi: true, pts: nil)))
    }

    func testExtractPTSSkipsAdaptationField() {
        var data = Data(capacity: 188)
        data.append(0x47)
        data.append(0x41)
        data.append(0x00)
        data.append(0x31)
        data.append(0x02)
        data.append(0xFF)
        data.append(0xFF)
        data.append(contentsOf: [0x00, 0x00, 0x01, 0xE0, 0x00, 0x00, 0xA0, 0x05])
        data.append(contentsOf: TSTestPacketFactory.ptsBytes(55.5))
        while data.count < 188 {
            data.append(0xFF)
        }
        XCTAssertEqual(TSParser.extractPTS(from: data) ?? -1, 55.5, accuracy: 0.001)
    }

    func testExtractPacketsAlignsAfterJunk() {
        var pending = Data(repeating: 0xAA, count: 7)
        for _ in 0..<3 {
            pending.append(TSTestPacketFactory.packet())
        }
        let packets = TSParser.extractPackets(pending: &pending)
        XCTAssertEqual(packets.count, 3)
        XCTAssertEqual(packets[0].count, 188)
        XCTAssertTrue(pending.isEmpty)
    }

    func testExtractPacketsHoldsPartialTail() {
        var pending = TSTestPacketFactory.packet()
        pending.append(TSTestPacketFactory.packet())
        pending.append(TSTestPacketFactory.packet().prefix(94))
        let packets = TSParser.extractPackets(pending: &pending)
        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual(pending.count, 94)
    }
}
