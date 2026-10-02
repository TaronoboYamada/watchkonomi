import SwiftUI

struct ChannelListView: View {
    @AppStorage("serverURLText") private var serverURLText = "https://100-111-2-73.local.konomi.tv:7000"
    @AppStorage("streamQuality") private var streamQuality = "240p"
    @State private var groups: [ChannelGroup] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var baseURL: URL {
        KonomiTVClient.sanitizedBaseURL(from: serverURLText) ?? URL(string: "https://100-111-2-73.local.konomi.tv:7000")!
    }

    var body: some View {
        Group {
            if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title3)
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.902, green: 0.310, blue: 0.592))
                        .multilineTextAlignment(.center)
                    Button("再読み込み") {
                        Task { await loadChannels() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        Section(group.label) {
                            ForEach(group.channels) { channel in
                                NavigationLink(value: channel) {
                                    ChannelRowView(channel: channel, baseURL: baseURL)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: serverURLText) {
            await loadChannels()
        }
        .navigationDestination(for: LiveChannel.self) { channel in
            PlayerView(channel: channel, baseURL: baseURL, quality: streamQuality)
        }
    }

    private func loadChannels() async {
        guard let url = KonomiTVClient.sanitizedBaseURL(from: serverURLText) else {
            errorMessage = "URLが不正です"
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            groups = try await KonomiTVClient(baseURL: url).fetchChannels()
        } catch {
            errorMessage = "サーバーに接続できません"
        }
        isLoading = false
    }
}

struct ChannelRowView: View {
    let channel: LiveChannel
    let baseURL: URL

    var body: some View {
        HStack(spacing: 6) {
            LogoView(url: KonomiTVClient(baseURL: baseURL).logoURL(for: channel))
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(channel.channelNumber) \(channel.name)")
                    .font(.caption)
                    .lineLimit(1)
                if let program = channel.programPresent {
                    Text("\(program.timeText) \(program.title)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("番組情報なし")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct LogoView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "tv")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            do {
                let (data, _) = try await KonomiTVClient.streamSession.data(from: url)
                image = UIImage(data: data)
            } catch {
                image = nil
            }
        }
    }
}


