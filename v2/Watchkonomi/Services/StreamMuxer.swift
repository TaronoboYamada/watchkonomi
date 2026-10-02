import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(Combine)
import Combine
#endif

final class StreamMuxer {
    enum MuxerState: Equatable {
        case idle
        case connecting
        case onair
        case failed(String)
    }

    #if canImport(SwiftUI)
    @Published private(set) var state: MuxerState = .idle
    #else
    private(set) var state: MuxerState = .idle
    #endif

    private let targetSegmentSeconds: Double
    private let windowSize: Int
    private let readySegments: Int

    private var pending = Data()
    private var current = Data()
    private var segmentStartPTS: Double?
    private var packetsWithoutPTS = 0
    private var segments: [(data: Data, duration: Double)] = []
    private(set) var firstMediaSequence = 0

    init(targetSegmentSeconds: Double = 2.0, windowSize: Int = 8, readySegments: Int = 3) {
        self.targetSegmentSeconds = targetSegmentSeconds
        self.windowSize = windowSize
        self.readySegments = readySegments
    }

    var isReady: Bool {
        segments.count >= readySegments
    }

    func beginConnection() {
        state = .connecting
    }

    func fail(_ message: String) {
        state = .failed(message)
    }

    func ingest(_ data: Data) {
        pending.append(data)
        let packets = TSParser.extractPackets(pending: &pending)
        for packet in packets {
            current.append(packet)
            if let pts = TSParser.extractPTS(from: packet) {
                if segmentStartPTS == nil {
                    segmentStartPTS = pts
                }
                packetsWithoutPTS = 0
                if let start = segmentStartPTS, pts - start >= targetSegmentSeconds {
                    finalizeSegment(duration: pts - start)
                }
            } else {
                packetsWithoutPTS += 1
                if packetsWithoutPTS >= 1500 {
                    finalizeSegment(duration: 0.0)
                }
            }
        }
    }

    func stop() {
        pending = Data()
        current = Data()
        segmentStartPTS = nil
        packetsWithoutPTS = 0
        segments = []
        firstMediaSequence = 0
        state = .idle
    }

    func playlist() -> String? {
        guard isReady else { return nil }
        let maxDuration = segments.map(\.duration).max() ?? targetSegmentSeconds
        let target = max(1, Int(ceil(maxDuration)))
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:\(target)",
            "#EXT-X-MEDIA-SEQUENCE:\(firstMediaSequence)",
        ]
        for segment in segments {
            lines.append(String(format: "#EXTINF:%.3f,", segment.duration))
        }
        return lines.joined(separator: "\n")
    }

    func segmentData(index: Int) -> Data? {
        let position = index - firstMediaSequence
        guard position >= 0, position < segments.count else { return nil }
        return segments[position].data
    }

    private func finalizeSegment(duration: Double) {
        segments.append((current, duration))
        current = Data()
        segmentStartPTS = nil
        packetsWithoutPTS = 0
        state = .onair
        while segments.count > windowSize {
            segments.removeFirst()
            firstMediaSequence += 1
        }
    }
}

#if canImport(SwiftUI)
extension StreamMuxer: ObservableObject {}
#endif
