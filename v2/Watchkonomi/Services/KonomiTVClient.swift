import Foundation

struct KonomiTVClient {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    static func sanitizedBaseURL(from text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            if value.contains("://") { return nil }
            value = "https://" + value
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    var channelsURL: URL {
        urlWithPath("/api/channels")
    }

    func logoURL(for channel: LiveChannel) -> URL {
        urlWithPath("/api/channels/\(channel.id)/logo")
    }

    func streamURL(displayChannelID: String, quality: String) -> URL {
        urlWithPath("/api/streams/live/\(displayChannelID)/\(quality)/mpegts")
    }

    private func urlWithPath(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL) ?? baseURL
    }
}
