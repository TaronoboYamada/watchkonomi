import SwiftUI

struct ContentView: View {
    @StateObject private var discovery = StreamDiscovery()
    @State private var activeURL: URL?

    var body: some View {
        Group {
            if let url = activeURL {
                PlayerView(url: url) {
                    activeURL = nil
                    discovery.stop()
                    discovery.start()
                }
            } else {
                idleView
            }
        }
        .onAppear {
            discovery.start()
        }
        .onChange(of: discovery.state) { _, newState in
            if case .found(let url) = newState {
                activeURL = url
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
            switch discovery.state {
            case .scanning:
                Text("iPhoneの配信を検出中です…")
                    .font(.caption2)
            case .found:
                EmptyView()
            }
            Text("iPhoneアプリで配信を開始してください")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
