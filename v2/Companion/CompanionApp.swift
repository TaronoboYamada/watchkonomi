import SwiftUI

@main
struct WatchkonomiCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Image(systemName: "applewatch")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(red: 0.902, green: 0.310, blue: 0.592))
                Text("Watchkonomi")
                    .font(.title2.bold())
                Text("このアプリは iPhone では動作しません。\nApple Watch にインストールしてください。")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
