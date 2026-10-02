import Foundation

enum KonomiTVError: Error {
    case notAStream
    case serverFailedToStart
    case httpError(Int)
}

final class InsecureTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

extension KonomiTVClient {
    private static let insecureDelegate = InsecureTrustDelegate()

    static let streamSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3600
        return URLSession(configuration: configuration, delegate: insecureDelegate, delegateQueue: nil)
    }()
}

enum StreamPump {
    static func run(url: URL, muxer: StreamMuxer, session: URLSession) async throws {
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw KonomiTVError.notAStream
        }
        var buffer = Data()
        buffer.reserveCapacity(65536)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 65536 {
                muxer.ingest(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            muxer.ingest(buffer)
        }
    }
}
