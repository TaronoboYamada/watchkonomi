import AVKit
import SwiftUI

struct PlayerView: View {
    let url: URL
    let onDisconnect: () -> Void

    @State private var player = AVPlayer()
    @State private var isMuted = false
    @State private var failed = false
    @State private var statusObservation: NSKeyValueObservation?

    var body: some View {
        ZStack {
            VideoPlayer(player: player)
                .ignoresSafeArea()

            if failed {
                VStack(spacing: 6) {
                    Image(systemName: "video.slash")
                        .font(.title3)
                    Text("ストリームが終了しました")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        isMuted.toggle()
                        player.isMuted = isMuted
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.2")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                if failed {
                    Button("閉じる", action: onDisconnect)
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 4)
                }
            }
            .padding(4)
        }
        .onAppear {
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            player.isMuted = isMuted
            player.play()
            statusObservation = item.observe(\.status) { item, _ in
                if item.status == .failed {
                    Task { @MainActor in
                        self.failed = true
                        self.player.pause()
                    }
                }
            }
        }
        .onDisappear {
            statusObservation = nil
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }
}
