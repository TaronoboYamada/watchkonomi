import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import ReplayKit

final class StreamerHandler: RPBroadcastSampleHandler {
    private var muxer: HLSMuxer?
    private var server: StreamServer?
    private var bonjour: NetService?
    private var ciContext: CIContext?
    private var rootDir: URL?

    private var targetVideoSize: (width: Int, height: Int)?
    private var firstVideoPTS: CMTime?
    private var lastEncodedPTS: CMTime?
    private var firstVideoDate: Date?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchkonomi-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        rootDir = dir

        ciContext = CIContext()
        muxer = HLSMuxer(rootDir: dir)

        let server = StreamServer(rootDir: dir)
        server.start()
        if server.waitReady(timeout: 5), server.port > 0 {
            self.server = server
            let service = NetService(
                domain: "",
                type: "_watchkonomi._tcp",
                name: "Watchkonomi-\(ProcessInfo.processInfo.processIdentifier)",
                port: Int32(server.port)
            )
            service.delegate = self
            service.publish()
            bonjour = service
        } else {
            NSLog("Watchkonomi: HTTP server did not start")
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            handleVideo(sampleBuffer)
        case .audioApp:
            handleAudio(sampleBuffer)
        case .audioMic:
            break
        @unknown default:
            break
        }
    }

    override func broadcastFinished() {
        server?.stop()
        bonjour?.stop()
        bonjour = nil
        muxer?.finish()
        if let dir = rootDir {
            try? FileManager.default.removeItem(at: dir)
        }
        muxer = nil
        server = nil
        ciContext = nil
        rootDir = nil
        targetVideoSize = nil
        firstVideoPTS = nil
        lastEncodedPTS = nil
        firstVideoDate = nil
    }

    // MARK: - Video

    private func handleVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if firstVideoPTS == nil {
            firstVideoPTS = pts
            firstVideoDate = Date()
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let targetHeight = 540
            let targetWidth = Int((Double(width) * Double(targetHeight) / Double(height)).rounded()) & ~1
            targetVideoSize = (width: targetWidth, height: targetHeight)
        }

        let minInterval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        if let last = lastEncodedPTS, CMTimeCompare(pts, CMTimeAdd(last, minInterval)) < 0 {
            return
        }
        lastEncodedPTS = pts

        guard let size = targetVideoSize, let ciContext else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = Double(size.height) / ciImage.extent.height
        let scaled = ciImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .cropped(to: CGRect(x: 0, y: 0, width: size.width, height: size.height))

        var output: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            size.width,
            size.height,
            kCVPixelFormatType_32BGRA,
            nil,
            &output
        ) == kCVReturnSuccess, let output else { return }

        ciContext.render(
            scaled,
            to: output,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )

        muxer?.appendVideo(
            output,
            config: HLSMuxer.VideoConfig(width: size.width, height: size.height),
            at: pts
        )
    }

    // MARK: - Audio

    private func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else { return }
        let asbd = asbdPointer.pointee
        guard
            asbd.mFormatID == kAudioFormatLinearPCM,
            asbd.mBitsPerChannel == 32,
            (asbd.mFormatFlags & kLinearPCMFormatFlagIsFloat) != 0
        else { return }

        let sampleRate = Double(asbd.mSampleRate)
        let channelCount = UInt32(asbd.mChannelsPerFrame)
        guard sampleRate > 0, channelCount > 0 else { return }

        muxer?.appendAudio(
            sampleBuffer,
            config: HLSMuxer.AudioConfig(sampleRate: sampleRate, channelCount: channelCount)
        )
    }
}

extension StreamerHandler: NetServiceDelegate {
    func netService(_ sender: NetService, didNotPublish error: Error) {
        NSLog("Watchkonomi: Bonjour publish failed: \(error)")
    }
}
