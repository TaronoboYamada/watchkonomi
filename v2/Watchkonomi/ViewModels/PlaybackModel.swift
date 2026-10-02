import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class PlaybackModel: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var muxer: StreamMuxer?
    @Published private(set) var server: LoopbackServer?
    @Published private(set) var failureMessage: String?

    private var pumpTask: Task<Void, Never>?

    func start(baseURL: URL, channel: LiveChannel, quality: String) async {
        stop()
        let muxer = StreamMuxer()
        let server = LoopbackServer()
        self.muxer = muxer
        self.server = server
        muxer.beginConnection()
        do {
            try await server.start(muxer: muxer)
        } catch {
            muxer.fail("サーバー起動に失敗しました")
            failureMessage = "サーバー起動に失敗しました"
            return
        }
        guard let playlistURL = server.playlistURL else { return }
        let streamURL = KonomiTVClient(baseURL: baseURL).streamURL(
            displayChannelID: channel.displayChannelID,
            quality: quality
        )
        pumpTask = Task.detached { [weak self] in
            do {
                try await StreamPump.run(url: streamURL, muxer: muxer, session: KonomiTVClient.streamSession)
                self?.muxer?.fail("ストリームが終了しました")
                self?.failureMessage = "ストリームが終了しました"
            } catch {
                self?.muxer?.fail("接続エラー")
                self?.failureMessage = "接続エラー"
            }
        }
        for _ in 0..<150 {
            if muxer.isReady { break }
            if case .failed = muxer.state { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard muxer.isReady else {
            muxer.fail("タイムアウト")
            failureMessage = "タイムアウト"
            return
        }
        let item = AVPlayerItem(url: playlistURL)
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func stop() {
        pumpTask?.cancel()
        pumpTask = nil
        server?.stop()
        server = nil
        muxer?.stop()
        muxer = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        failureMessage = nil
    }
}
