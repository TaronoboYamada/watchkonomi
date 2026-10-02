import Foundation

struct LiveChannel: Codable, Identifiable, Hashable {
    let id: String
    let displayChannelID: String
    let channelNumber: String
    let type: String
    let name: String
    let isRadiochannel: Bool
    let isDisplay: Bool
    let programPresent: LiveProgram?

    enum CodingKeys: String, CodingKey {
        case id
        case displayChannelID = "display_channel_id"
        case channelNumber = "channel_number"
        case type
        case name
        case isRadiochannel = "is_radiochannel"
        case isDisplay = "is_display"
        case programPresent = "program_present"
    }
}

struct LiveProgram: Codable, Hashable {
    let title: String
    let description: String?
    let startTime: String
    let endTime: String

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case startTime = "start_time"
        case endTime = "end_time"
    }

    var timeText: String {
        "\(String(startTime.dropFirst(11).prefix(5)))-\(String(endTime.dropFirst(11).prefix(5)))"
    }
}

struct LiveChannelsResponse: Codable {
    let gr: [LiveChannel]
    let bs: [LiveChannel]
    let cs: [LiveChannel]
    let catv: [LiveChannel]
    let sky: [LiveChannel]
    let bs4k: [LiveChannel]

    enum CodingKeys: String, CodingKey {
        case gr = "GR"
        case bs = "BS"
        case cs = "CS"
        case catv = "CATV"
        case sky = "SKY"
        case bs4k = "BS4K"
    }
}

struct ChannelGroup: Hashable {
    let label: String
    let channels: [LiveChannel]
}

extension LiveChannelsResponse {
    var groups: [ChannelGroup] {
        [
            ChannelGroup(label: "地デジ", channels: gr.filter { $0.isDisplay }),
            ChannelGroup(label: "BS", channels: bs.filter { $0.isDisplay }),
            ChannelGroup(label: "CS", channels: cs.filter { $0.isDisplay }),
            ChannelGroup(label: "CATV", channels: catv.filter { $0.isDisplay }),
            ChannelGroup(label: "SKY", channels: sky.filter { $0.isDisplay }),
            ChannelGroup(label: "BS4K", channels: bs4k.filter { $0.isDisplay }),
        ]
    }
}
