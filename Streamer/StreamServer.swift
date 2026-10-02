import Foundation
import Network

final class StreamServer {
    private let rootDir: URL
    private let queue = DispatchQueue(label: "watchkonomi.stream.server")
    private let readySemaphore = DispatchSemaphore(value: 0)
    private var listener: NWListener?
    private var portValue: UInt16 = 0

    var port: UInt16 {
        portValue
    }

    init(rootDir: URL) {
        self.rootDir = rootDir
    }

    func start() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let parameters = NWParameters.tcp
            guard let listener = try? NWListener(using: parameters, on: .any) else {
                self.readySemaphore.signal()
                return
            }
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = listener.port {
                        self.portValue = port.rawValue
                    }
                    self.readySemaphore.signal()
                case .failed(let error):
                    NSLog("Watchkonomi: stream server failed: \(error)")
                    self.readySemaphore.signal()
                default:
                    break
                }
            }
            listener.start(queue: self.queue)
        }
        queue.async(execute: work)
    }

    func waitReady(timeout: TimeInterval) -> Bool {
        readySemaphore.wait(timeout: .now() + timeout) == .success
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHeaders(connection, into: Data()) { [weak self] success, data in
            guard success, let self else {
                connection.cancel()
                return
            }
            self.serve(connection: connection, request: data)
        }
    }

    private func receiveHeaders(_ connection: NWConnection, into data: Data, completion: @escaping (Bool, Data) -> Void) {
        let terminator = Data("\r\n\r\n".utf8)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] chunk, _, _, error in
            if let error {
                NSLog("Watchkonomi: receive error: \(error)")
                completion(false, data)
                return
            }
            guard let chunk else {
                completion(false, data)
                return
            }
            var data = data
            data.append(chunk)
            if data.range(of: terminator) != nil {
                completion(true, data)
                return
            }
            if data.count > 65_536 {
                completion(false, data)
                return
            }
            guard let self else {
                completion(false, data)
                return
            }
            self.receiveHeaders(connection, into: data, completion: completion)
        }
    }

    private func serve(connection: NWConnection, request: Data) {
        guard let requestString = String(data: request, encoding: .utf8) else {
            connection.cancel()
            return
        }
        let firstLine = requestString.split(separator: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(connection, status: 400, body: Data())
            return
        }
        let method = String(parts[0])
        let rawPath = String(parts[1])
        let pathOnly = rawPath.split(separator: "?").first.map(String.init) ?? rawPath

        guard method == "GET" || method == "HEAD" else {
            respond(connection, status: 405, body: Data())
            return
        }

        let name = (pathOnly as NSString).lastPathComponent
        guard name.hasSuffix(".m3u8") || name.hasSuffix(".ts") else {
            respond(connection, status: 404, body: Data())
            return
        }

        let fileURL = rootDir.appendingPathComponent(name)
        guard let body = try? Data(contentsOf: fileURL) else {
            respond(connection, status: 404, body: Data())
            return
        }

        let contentType = name.hasSuffix(".m3u8") ? "application/vnd.apple.mpegurl" : "video/mp2t"
        respond(connection, status: 200, contentType: contentType, body: body, headOnly: method == "HEAD")
    }

    private func respond(
        _ connection: NWConnection,
        status: Int,
        contentType: String = "application/octet-stream",
        body: Data,
        headOnly: Bool = false
    ) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }
        var response = "HTTP/1.1 \(status) \(reason)\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Cache-Control: no-cache\r\n"
        response += "Connection: close\r\n\r\n"

        var payload = Data(response.utf8)
        if !headOnly {
            payload.append(body)
        }
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
