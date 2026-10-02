import Foundation

@MainActor
final class StreamDiscovery: NSObject, ObservableObject {
    enum State: Equatable {
        case scanning
        case found(URL)
    }

    @Published private(set) var state: State = .scanning

    private let browser = NSNetServiceBrowser()
    private var resolvingService: NSNetService?

    func start() {
        guard browser.isSearching == false else { return }
        browser.delegate = self
        browser.searchForServices(withDomain: "", type: "_watchkonomi._tcp")
    }

    func stop() {
        browser.stop()
        browser.delegate = nil
        resolvingService = nil
        state = .scanning
    }
}

extension StreamDiscovery: NSNetServiceBrowserDelegate {
    nonisolated func netServiceBrowser(_ browser: NSNetServiceBrowser, didFind service: NSNetService, moreComing: Bool) {
        Task { @MainActor in
            guard case .scanning = self.state else { return }
            self.resolvingService = service
            service.delegate = self
            browser.resolve(service, timeout: 5)
        }
    }

    nonisolated func netServiceBrowser(_ browser: NSNetServiceBrowser, didRemove service: NSNetService, moreComing: Bool) {
        Task { @MainActor in
            if self.resolvingService === service {
                self.resolvingService = nil
                self.state = .scanning
            }
        }
    }
}

extension StreamDiscovery: NSNetServiceDelegate {
    nonisolated func netServiceDidResolveAddress(_ sender: NSNetService) {
        Task { @MainActor in
            guard let ip = Self.ipv4Address(from: sender) else { return }
            let port = sender.port
            guard let url = URL(string: "http://\(ip):\(port)/index.m3u8") else { return }
            self.state = .found(url)
        }
    }

    nonisolated func netService(_ sender: NSNetService, didNotResolve error: Error) {
        Task { @MainActor in
            if self.resolvingService === sender {
                self.resolvingService = nil
                self.state = .scanning
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
