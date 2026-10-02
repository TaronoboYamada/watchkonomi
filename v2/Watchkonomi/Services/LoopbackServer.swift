import Foundation
import Network

final class LoopbackServer {
    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private var muxer: StreamMuxer?

    var playlistURL: URL? {
        port == 0 ? nil : URL(string: "http://127.0.0.1:\(port)/live.m3u8")
    }

    func start(muxer: StreamMuxer) async throws {
        self.muxer = muxer
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .name("127.0.0.1"),
            port: .any
        )
        let listener = NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            HTTPConnectionHandler(connection: connection, server: self).start()
        }
        listener.start(queue: .global())
        self.listener = listener
        for _ in 0..<100 {
            if let endpointPort = listener.port, endpointPort.rawValue != 0 {
                port = endpointPort.rawValue
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        listener.cancel()
        self.listener = nil
        throw KonomiTVError.serverFailedToStart
    }

    func stop() {
        listener?.cancel()
        listener = nil
        muxer = nil
        port = 0
    }

    func route(path: String) -> (status: String, contentType: String, body: Data) {
        guard let muxer else {
            return ("503 Service Unavailable", "text/plain", Data())
        }
        if path == "/live.m3u8" {
            if let playlist = muxer.playlist() {
                return ("200 OK", "application/vnd.apple.mpegurl", Data(playlist.utf8))
            }
            return ("503 Service Unavailable", "text/plain", Data())
        }
        if path.hasPrefix("/seg"), path.hasSuffix(".ts") {
            let indexText = path.dropFirst(4).dropLast(3)
            if let index = Int(indexText), let data = muxer.segmentData(index: index) {
                return ("200 OK", "video/mp2t", data)
            }
            return ("404 Not Found", "text/plain", Data())
        }
        return ("404 Not Found", "text/plain", Data())
    }
}

private final class HTTPConnectionHandler {
    private let connection: NWConnection
    private let server: LoopbackServer
    private var buffer = Data()
    private var done = false

    init(connection: NWConnection, server: LoopbackServer) {
        self.connection = connection
        self.server = server
    }

    func start() {
        connection.start(queue: .global())
        receiveMore()
    }

    private func receiveMore() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, !self.done else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                let terminator = Data([0x0D, 0x0A, 0x0D, 0x0A])
                if let range = self.buffer.range(of: terminator) {
                    let headBytes = self.buffer.prefix(upTo: range.lowerBound)
                    let head = String(data: Data(headBytes), encoding: .utf8) ?? ""
                    self.finish(with: head)
                    return
                }
                if self.buffer.count > 8192 {
                    self.done = true
                    self.connection.cancel()
                    return
                }
            }
            self.receiveMore()
        }
    }

    private func finish(with requestHead: String) {
        done = true
        let path = Self.parsePath(requestHead)
        let (status, contentType, body) = server.route(path: path)
        var response = "HTTP/1.1 \(status)\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Cache-Control: no-store\r\n"
        response += "Connection: close\r\n\r\n"
        var data = Data(response.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in
            self.connection.cancel()
        })
    }

    private static func parsePath(_ requestHead: String) -> String {
        let firstLine = requestHead.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return "" }
        return parts[1]
    }
}
