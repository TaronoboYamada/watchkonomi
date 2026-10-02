import Foundation
import Network

@MainActor
final class StreamDiscovery: ObservableObject {
    enum State: Equatable {
        case scanning
        case found(URL)
    }

    @Published private(set) var state: State = .scanning

    private var browser: NWBrowser?
    private var connection: NWConnection?

    func start() {
        guard browser == nil else { return }
        state = .scanning

        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: "_watchkonomi._tcp", domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, case .scanning = self.state, let result = results.first else { return }
                self.connect(to: result.endpoint)
            }
        }
        browser.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                if case .failed = newState {
                    self.browser?.cancel()
                    self.browser = nil
                    self.connection?.cancel()
                    self.connection = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        self.start()
                    }
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        state = .scanning
    }

    private func connect(to endpoint: NWEndpoint) {
        connection?.cancel()
        let connection = NWConnection(to: endpoint, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                switch newState {
                case .ready:
                    if let url = Self.streamURL(for: connection) {
                        self.state = .found(url)
                    } else {
                        self.connection?.cancel()
                        self.connection = nil
                        self.state = .scanning
                    }
                case .failed:
                    self.connection?.cancel()
                    self.connection = nil
                    self.state = .scanning
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    private static func streamURL(for connection: NWConnection) -> URL? {
        var hostText: String?
        var portValue: UInt16?

        if let remote = connection.currentPath?.remoteEndpoint,
           case let .hostPort(host, port) = remote {
            hostText = Self.hostText(host)
            portValue = port.rawValue
        } else if case let .hostPort(host, port) = connection.endpoint {
            hostText = Self.hostText(host)
            portValue = port.rawValue
        }

        guard let hostText, let portValue else { return nil }
        return URL(string: "http://\(hostText):\(portValue)/index.m3u8")
    }

    private static func hostText(_ host: NWEndpoint.Host) -> String {
        var text = "\(host)".replacingOccurrences(of: ".local.", with: ".local")
        if text.hasSuffix(".") { text.removeLast() }
        if text.contains(":") && !text.hasPrefix("[") {
            text = "[\(text)]"
        }
        return text
    }
}
