import AVKit
import SwiftUI

struct PlayerView: View {
    let channel: LiveChannel
    let baseURL: URL
    let quality: String

    @StateObject private var model = PlaybackModel()
    @State private var isMuted = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            if model.server != nil {
                VideoPlayer(player: model.player)
                    .ignoresSafeArea()
            }
            overlay
        }
        .onAppear {
            Task {
                await model.start(baseURL: baseURL, channel: channel, quality: quality)
            }
        }
        .onDisappear {
            model.stop()
        }
    }

    @ViewBuilder
    private var overlay: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button {
                    isMuted.toggle()
                    model.player.isMuted = isMuted
                } label: {
                    Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            if let state = model.muxer?.state {
                switch state {
                case .failed(let message):
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash")
                            .font(.title3)
                        Text(message)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 4)
                case .connecting:
                    ProgressView()
                        .padding(.bottom, 4)
                default:
                    if let program = channel.programPresent {
                        VStack(spacing: 2) {
                            Text("\(channel.channelNumber) \(channel.name)")
                                .font(.caption)
                            Text(program.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 4)
                    }
                }
            }
        }
        .padding(4)
    }
}
