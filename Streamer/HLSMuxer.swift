import AVFoundation
import CoreMedia
import Foundation

final class HLSMuxer {
    struct VideoConfig {
        let width: Int
        let height: Int
    }

    struct AudioConfig {
        let sampleRate: Double
        let channelCount: UInt32
    }

    private enum State {
        case notStarted
        case running
        case rotating
        case stopped
    }

    private let rootDir: URL
    private let segmentDuration = CMTime(seconds: 4, preferredTimescale: 600)
    private let maxSegments = 8
    private let lock = NSLock()

    private var state: State = .notStarted
    private var isFinishing = false
    private var videoConfig: VideoConfig?
    private var audioConfig: AudioConfig?
    private var firstSampleDate: Date?

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var segmentIndex = 0
    private var mediaSequence = 0
    private var segmentStartPTS: CMTime?
    private var sessionStarted = false
    private var segments: [String] = []

    init(rootDir: URL) {
        self.rootDir = rootDir
        try? FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        writePlaylist()
    }

    // MARK: - Video

    func appendVideo(_ pixelBuffer: CVPixelBuffer, config: VideoConfig, at pts: CMTime) {
        lock.lock()
        defer { lock.unlock() }

        if state == .notStarted {
            videoConfig = config
            firstSampleDate = firstSampleDate ?? Date()
            maybeStart()
        }
        guard state == .running, let writer, let videoInput else { return }
        guard writer.status == .writing, videoInput.isReadyForMoreMediaData else {
            if writer.status == .failed {
                state = .stopped
            }
            return
        }
        guard let sampleBuffer = Self.makeSampleBuffer(from: pixelBuffer, at: pts) else { return }
        ensureSessionStarted(writer: writer, at: pts)
        videoInput.append(sampleBuffer)
        checkSegmentBoundary(at: pts)
    }

    // MARK: - Audio

    func appendAudio(_ pcmBuffer: AVAudioPCMBuffer, config: AudioConfig, at pts: CMTime) {
        lock.lock()
        defer { lock.unlock() }

        if state == .notStarted {
            audioConfig = config
            firstSampleDate = firstSampleDate ?? Date()
            maybeStart()
        }
        guard state == .running, let writer, let audioInput else { return }
        guard writer.status == .writing, audioInput.isReadyForMoreMediaData else {
            if writer.status == .failed {
                state = .stopped
            }
            return
        }
        guard let sampleBuffer = Self.makeAudioSampleBuffer(from: pcmBuffer, at: pts) else { return }
        ensureSessionStarted(writer: writer, at: pts)
        audioInput.append(sampleBuffer)
    }

    // MARK: - Lifecycle

    func finish() {
        lock.lock()
        defer { lock.unlock() }

        isFinishing = true
        if state == .running {
            rotateSegment()
        } else if state != .rotating {
            state = .stopped
        }
    }

    // MARK: - Writer management

    private func maybeStart() {
        guard state == .notStarted, let videoConfig else { return }
        if let audioConfig {
            startWriter(video: videoConfig, audio: audioConfig)
        } else if let firstDate = firstSampleDate, Date().timeIntervalSince(firstDate) > 1.0 {
            startWriter(video: videoConfig, audio: AudioConfig(sampleRate: 44100, channelCount: 2))
        }
    }

    private func startWriter(video: VideoConfig, audio: AudioConfig) {
        segmentIndex += 1
        do {
            let writer = try AVAssetWriter(outputURL: segmentURL(index: segmentIndex), fileType: .mpeg2TransportStream)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: video.width,
                AVVideoHeightKey: video.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 800_000,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoAllowFrameReorderingKey: false,
                ],
            ]
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: audio.sampleRate,
                AVNumberOfChannelsKey: audio.channelCount,
                AVEncoderBitRateKey: 96_000,
            ]

            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true

            writer.add(videoInput)
            writer.add(audioInput)
            writer.startWriting()

            self.writer = writer
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.segmentStartPTS = nil
            self.sessionStarted = false
            self.state = .running
        } catch {
            NSLog("Watchkonomi: AVAssetWriter start failed: \(error)")
            state = .stopped
        }
    }

    private func ensureSessionStarted(writer: AVAssetWriter, at pts: CMTime) {
        guard !sessionStarted else { return }
        writer.startSession(atSourceTime: pts)
        sessionStarted = true
        segmentStartPTS = pts
    }

    private func checkSegmentBoundary(at pts: CMTime) {
        guard let start = segmentStartPTS else { return }
        guard CMTimeCompare(pts, start.adding(segmentDuration)) >= 0 else { return }
        rotateSegment()
    }

    private func rotateSegment() {
        guard let writer, let videoInput, let audioInput else { return }
        state = .rotating
        videoInput.markAsFinished()
        audioInput.markAsFinished()
        writer.finishWriting { [weak self] _ in
            self?.segmentCompleted()
        }
    }

    private func segmentCompleted() {
        lock.lock()
        defer { lock.unlock() }
        guard state == .rotating else { return }

        segments.append(segmentName(index: segmentIndex))
        if segments.count > maxSegments {
            let removed = segments.removeFirst()
            try? FileManager.default.removeItem(at: rootDir.appendingPathComponent(removed))
        }
        mediaSequence += 1
        writePlaylist()

        if isFinishing {
            state = .stopped
        } else if let videoConfig, let audioConfig {
            startWriter(video: videoConfig, audio: audioConfig)
        } else {
            state = .stopped
        }
    }

    // MARK: - Playlist

    private func writePlaylist() {
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:5",
            "#EXT-X-MEDIA-SEQUENCE:\(mediaSequence)",
            "#EXT-X-PLAYLIST-TYPE:LIVE",
            "#EXT-X-ALLOW-CACHE:NO",
        ]
        for name in segments {
            lines.append("#EXTINF:4.000000,")
            lines.append(name)
        }
        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(to: rootDir.appendingPathComponent("index.m3u8"), atomically: true, encoding: .utf8)
    }

    private func segmentName(index: Int) -> String {
        String(format: "seg_%06d.ts", index)
    }

    private func segmentURL(index: Int) -> URL {
        rootDir.appendingPathComponent(segmentName(index: index))
    }

    // MARK: - Sample buffer wrapping

    private static func makeAudioSampleBuffer(from pcmBuffer: AVAudioPCMBuffer, at pts: CMTime) -> CMSampleBuffer? {
        let format = pcmBuffer.format
        let byteSize = Int(pcmBuffer.frameLength) * Int(format.channelCount) * 4
        guard byteSize > 0, let channelData = pcmBuffer.floatChannelData else { return nil }

        var blockBuffer: CMBlockBuffer?
        guard
            CMBlockBufferCreate(
                allocator: kCFAllocatorDefault,
                dataPointer: nil,
                dataLength: byteSize,
                dataToBeFree: nil,
                allocatorContext: nil,
                offsetWithinData: 0,
                lengthOfData: byteSize,
                mergeMethod: .noMerge,
                blockBufferOut: &blockBuffer
            ) == noErr,
            let blockBuffer
        else { return nil }

        let channelCount = Int(format.channelCount)
        for channel in 0..<channelCount {
            let channelByteSize = Int(pcmBuffer.frameLength) * 4
            let offset = channel * channelByteSize
            CMBlockBufferReplaceDataBytes(
                blockBuffer,
                dataLength: channelByteSize,
                offset: offset,
                pointer: channelData[channel]
            )
        }

        var asbd = format.streamDescription
        var formatDescription: CMAudioFormatDescription?
        guard
            CMAudioFormatDescriptionCreate(
                kCFAllocatorDefault, &asbd, 0, nil, &formatDescription
            ) == noErr,
            let formatDescription
        else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(pcmBuffer.frameLength), timescale: CMTimeScale(format.sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard
            CMSampleBufferCreate(
                blockBuffer: blockBuffer,
                formatDescription: formatDescription,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                sampleTimingEntry: &timing,
                sampleEntryCount: 1,
                sampleBufferOut: &sampleBuffer
            ) == noErr,
            let sampleBuffer
        else { return nil }

        return sampleBuffer
    }

    private static func makeSampleBuffer(from pixelBuffer: CVPixelBuffer, at pts: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        guard
            CMVideoFormatDescriptionCreateForImageBuffer(
                kCFAllocatorDefault, pixelBuffer, false, nil, &formatDescription
            ) == noErr,
            let formatDescription
        else { return nil }

        var blockBuffer: CMBlockBuffer?
        guard
            CMBlockBufferCreateAccessible(
                fromCVPixelBuffer: pixelBuffer,
                pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer),
                planeIndex: 0,
                options: [],
                blockBufferOut: &blockBuffer
            ) == noErr,
            let blockBuffer
        else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard
            CMSampleBufferCreate(
                blockBuffer: blockBuffer,
                formatDescription: formatDescription,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                sampleTimingEntry: &timing,
                sampleEntryCount: 1,
                sampleBufferOut: &sampleBuffer
            ) == noErr,
            let sampleBuffer
        else { return nil }

        return sampleBuffer
    }
}
