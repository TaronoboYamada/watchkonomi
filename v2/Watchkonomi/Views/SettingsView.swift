import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURLText") private var serverURLText = "https://100-111-2-73.local.konomi.tv:7000"
    @AppStorage("streamQuality") private var streamQuality = "240p"
    @State private var invalidURL = false
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        List {
            Section("サーバー") {
                TextField("https://…:7000", text: $serverURLText)
                if invalidURL {
                    Text("URLが不正です")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.902, green: 0.310, blue: 0.592))
                }
            }
            Section("画質") {
                Picker("画質", selection: $streamQuality) {
                    ForEach(StreamQuality.allCases) { quality in
                        Text(quality.label).tag(quality.rawValue)
                    }
                }
            }
            Section("接続") {
                Button {
                    Task { await testConnection() }
                } label: {
                    if isTesting {
                        ProgressView()
                    } else {
                        Text("接続テスト")
                    }
                }
                if let testResult {
                    Text(testResult)
                        .font(.caption2)
                }
            }
        }
        .onChange(of: serverURLText) { _, newValue in
            invalidURL = KonomiTVClient.sanitizedBaseURL(from: newValue) == nil
        }
    }

    private func testConnection() async {
        guard let url = KonomiTVClient.sanitizedBaseURL(from: serverURLText) else {
            testResult = "URLが不正です"
            return
        }
        isTesting = true
        do {
            let groups = try await KonomiTVClient(baseURL: url).fetchChannels()
            let count = groups.reduce(0) { $0 + $1.channels.count }
            testResult = "接続OK(チャンネル\(count)件)"
        } catch {
            testResult = "接続できませんでした"
        }
        isTesting = false
    }
}
