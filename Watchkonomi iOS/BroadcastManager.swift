import Foundation
import ReplayKit

@MainActor
final class BroadcastManager: NSObject, ObservableObject {
    @Published private(set) var isStreaming = false
    @Published private(set) var streamURL: String?
    @Published private(set) var lastError: String?

    private let controller = RPBroadcastController()
    private let browser = NSNetServiceBrowser()
    private var resolvingService: NSNetService?

    override init() {
        super.init()
        controller.delegate = self
        controller.broadcastExtensionBundleID = "com.example.watchkonomi.ios.streamer"
        browser.delegate = self
        browser.searchForServices(withDomain: "", type: "_watchkonomi._tcp")
    }

    func start() {
        lastError = nil
        controller.startBroadcast { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    func stop() {
        controller.finishBroadcast { _ in }
    }
}

extension BroadcastManager: RPBroadcastControllerDelegate {
    nonisolated func broadcastController(_ controller: RPBroadcastController, didFinishWithError error: (any Error)?) {
        Task { @MainActor in
            self.isStreaming = false
            if let error {
                self.lastError = error.localizedDescription
            }
        }
    }
}

extension BroadcastManager: NSNetServiceBrowserDelegate {
    nonisolated func netServiceBrowser(_ browser: NSNetServiceBrowser, didFind service: NSNetService, moreComing: Bool) {
        Task { @MainActor in
            guard self.streamURL == nil else { return }
            self.resolvingService = service
            service.delegate = self
            browser.resolve(service, timeout: 5)
        }
    }

    nonisolated func netServiceBrowser(_ browser: NSNetServiceBrowser, didRemove service: NSNetService, moreComing: Bool) {
        Task { @MainActor in
            if self.resolvingService === service {
                self.resolvingService = nil
                self.isStreaming = false
                self.streamURL = nil
            }
        }
    }
}

extension BroadcastManager: NSNetServiceDelegate {
    nonisolated func netServiceDidResolveAddress(_ sender: NSNetService) {
        Task { @MainActor in
            guard let ip = Self.ipv4Address(from: sender) else { return }
            let port = sender.port
            self.isStreaming = true
            self.streamURL = "http://\(ip):\(port)/index.m3u8"
        }
    }

    nonisolated func netService(_ sender: NSNetService, didNotResolve error: Error) {
        Task { @MainActor in
            if self.resolvingService === sender {
                self.resolvingService = nil
            }
        }
    }

    static func ipv4Address(from service: NSNetService) -> String? {
        for raw in service.addresses {
            let bytes = [UInt8](raw as Data)
            guard bytes.count >= 8 else { continue }
            let family = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            if family == UInt16(AF_INET) {
                return "\(bytes[4]).\(bytes[5]).\(bytes[6]).\(bytes[7])"
            }
        }
        return nil
    }
}
