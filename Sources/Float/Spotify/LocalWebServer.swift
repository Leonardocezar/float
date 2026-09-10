import Foundation
import Network

final class LocalWebServer {
    private var listener: NWListener?
    private let html: String
    private(set) var port: UInt16 = 0

    init(html: String) { self.html = html }

    var url: URL? {
        port == 0 ? nil : URL(string: "http://127.0.0.1:\(port)/")
    }

    func start() async throws -> URL {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: params)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in self?.serve(conn) }

        return try await withCheckedThrowingContinuation { cont in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let raw = listener.port?.rawValue {
                        self?.port = raw
                        cont.resume(returning: URL(string: "http://127.0.0.1:\(raw)/")!)
                    }
                case .failed(let error):
                    cont.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }

            let path = Self.requestPath(from: data) ?? "/"
            let response: Data
            if path == "/" || path.hasPrefix("/?") {
                response = Self.httpResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: self.html)
            } else {
                response = Self.httpResponse(status: "404 Not Found", contentType: "text/plain", body: "not found")
            }
            conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    private static func requestPath(from data: Data?) -> String? {
        guard let data, let text = String(data: data, encoding: .utf8),
              let line = text.split(separator: "\r\n").first else { return nil }
        let parts = line.split(separator: " ")
        return parts.count >= 2 ? String(parts[1]) : nil
    }

    private static func httpResponse(status: String, contentType: String, body: String) -> Data {
        let bytes = Array(body.utf8)
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(bytes.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        return Data(header.utf8) + Data(bytes)
    }
}
