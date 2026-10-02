import XCTest
@testable import WK

final class ChannelTests: XCTestCase {

    let fixture = """
    {"GR":[{"id":"NID32736-SID1024","display_channel_id":"gr011","channel_number":"011","type":"GR",
    "name":"NHK総合","jikkyo_force":10,"is_subchannel":false,"is_radiochannel":false,"is_watchable":true,
    "terrestrial_regions":["東京"],"is_display":true,"viewer_count":2,
    "program_present":{"title":"ニュース","description":null,"detail":{},
    "start_time":"2026-10-02T19:00:00+09:00","end_time":"2026-10-02T20:00:00+09:00","is_free":true,"genres":[]},
    "program_following":null}],
    "BS":[],"CS":[],"CATV":[],"SKY":[],"BS4K":[]}
    """

    func testDecodeLiveChannelsResponse() throws {
        let decoded = try JSONDecoder().decode(LiveChannelsResponse.self, from: fixture.data(using: .utf8)!)
        XCTAssertEqual(decoded.gr.count, 1)
        XCTAssertEqual(decoded.gr[0].displayChannelID, "gr011")
        XCTAssertEqual(decoded.gr[0].channelNumber, "011")
        XCTAssertEqual(decoded.gr[0].programPresent?.title, "ニュース")
        XCTAssertEqual(decoded.gr[0].programPresent?.timeText, "19:00-20:00")
    }

    func testDecodeNullProgramPresent() throws {
        let nullFixture = """
        {"GR":[{"id":"NID32736-SID1024","display_channel_id":"gr011","channel_number":"011","type":"GR",
        "name":"NHK総合","is_radiochannel":false,"is_display":true,
        "program_present":null,"program_following":null}],
        "BS":[],"CS":[],"CATV":[],"SKY":[],"BS4K":[]}
        """
        let decoded = try JSONDecoder().decode(LiveChannelsResponse.self, from: nullFixture.data(using: .utf8)!)
        XCTAssertNil(decoded.gr[0].programPresent)
    }

    func testGroupsFiltersHiddenAndLabels() throws {
        let json = """
        {"GR":[{"id":"NID1-SID1","display_channel_id":"gr001","channel_number":"001","type":"GR","name":"A","is_radiochannel":false,"is_display":true,"program_present":null}],
        "BS":[{"id":"NID2-SID2","display_channel_id":"bs099","channel_number":"099","type":"BS","name":"B","is_radiochannel":false,"is_display":false,"program_present":null}],
        "CS":[],"CATV":[],"SKY":[],"BS4K":[]}
        """
        let decoded = try JSONDecoder().decode(LiveChannelsResponse.self, from: json.data(using: .utf8)!)
        let groups = decoded.groups
        XCTAssertEqual(groups.map(\.label), ["地デジ", "BS", "CS", "CATV", "SKY", "BS4K"])
        XCTAssertEqual(groups[0].channels.count, 1)
        XCTAssertEqual(groups[1].channels.count, 0)
    }
}
