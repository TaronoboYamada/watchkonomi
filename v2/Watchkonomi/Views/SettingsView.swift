import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURLText") private var serverURLText = "https://100-111-2-73.local.konomi.tv:7000"
    @AppStorage("streamQuality") private var streamQuality = "240p"
    @State private var invalidURL = false

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
            // TODO(Task 7c): 接続テストボタン
        }
        .onChange(of: serverURLText) { _, newValue in
            invalidURL = KonomiTVClient.sanitizedBaseURL(from: newValue) == nil
        }
    }
}
