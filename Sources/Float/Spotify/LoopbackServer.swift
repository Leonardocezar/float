import Foundation
import Network

final class LoopbackServer {
    enum ServerError: Error { case badRequest, cancelled }

    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?

    let port: UInt16

    init(port: UInt16) { self.port = port }

    func waitForRedirect() async throws -> [String: String] {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            do {
                let params = NWParameters.tcp
                params.requiredLocalEndpoint = NWEndpoint.hostPort(
                    host: .ipv4(.loopback),
                    port: NWEndpoint.Port(rawValue: port)!
                )
                let listener = try NWListener(using: params)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] conn in
                    self?.handle(conn)
                }
                listener.start(queue: .main)
            } catch {
                cont.resume(throwing: error)
                self.continuation = nil
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if let cont = continuation {
            continuation = nil
            cont.resume(throwing: ServerError.cancelled)
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return }
            defer {
                let body = "Float is connected to Spotify. You can close this tab."
                let response = """
                HTTP/1.1 200 OK\r
                Content-Type: text/plain; charset=utf-8\r
                Content-Length: \(body.utf8.count)\r
                Connection: close\r
                \r
                \(body)
                """
                conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    conn.cancel()
                })
            }

            guard
                let data,
                let request = String(data: data, encoding: .utf8),
                let requestLine = request.split(separator: "\r\n").first,
                let pathPart = requestLine.split(separator: " ").dropFirst().first,
                let comps = URLComponents(string: "http://127.0.0.1\(pathPart)")
            else {
                self.resume(.failure(ServerError.badRequest))
                return
            }

            var items: [String: String] = [:]
            for q in comps.queryItems ?? [] { items[q.name] = q.value }
            self.resume(.success(items))
        }
    }

    private func resume(_ result: Result<[String: String], Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        listener?.cancel()
        listener = nil
        cont.resume(with: result)
    }
}
