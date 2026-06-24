import Foundation
import Network

final class AgentEventServer {
    static let port: UInt16 = 47_832

    private let token: String
    private let onEvent: (AgentEvent) -> Void
    private let onFailure: (Error) -> Void
    private let queue = DispatchQueue(label: "com.airsentry.agent-events", qos: .utility)
    private var listener: NWListener?

    init(token: String, onEvent: @escaping (AgentEvent) -> Void, onFailure: @escaping (Error) -> Void) {
        self.token = token
        self.onEvent = onEvent
        self.onFailure = onFailure
    }

    func start() throws {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: Self.port)!
        )

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.receiveRequest(on: connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case let .failed(error) = state {
                NSLog("AirSentry agent event listener failed: %@", String(describing: error))
                self?.onFailure(error)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.start(queue: queue)
        receiveChunk(on: connection, accumulated: Data())
    }

    private func receiveChunk(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }

            var requestData = accumulated
            if let data { requestData.append(data) }
            guard requestData.count <= 1_048_576 else {
                self.respond(to: connection, accepted: false)
                return
            }

            if self.hasCompleteRequest(requestData) || isComplete {
                let accepted = self.decodeRequest(requestData).map { event in
                    self.onEvent(event)
                    return true
                } ?? false
                self.respond(to: connection, accepted: accepted)
            } else {
                self.receiveChunk(on: connection, accumulated: requestData)
            }
        }
    }

    private func hasCompleteRequest(_ data: Data) -> Bool {
        guard let request = String(data: data, encoding: .utf8),
              let separator = request.range(of: "\r\n\r\n") else { return false }
        let headers = String(request[..<separator.lowerBound])
        let contentLength = headers
            .components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("content-length:") })
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") }
        guard let contentLength else { return true }
        return request[separator.upperBound...].utf8.count >= contentLength
    }

    private func respond(to connection: NWConnection, accepted: Bool) {
        let status = accepted ? "202 Accepted" : "400 Bad Request"
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func decodeRequest(_ data: Data) -> AgentEvent? {
        guard let request = String(data: data, encoding: .utf8),
              let separator = request.range(of: "\r\n\r\n") else { return nil }

        let headers = String(request[..<separator.lowerBound])
        guard headers.hasPrefix("POST /events "),
              headers.range(
                of: "X-AirSentry-Token: \(token)",
                options: [.caseInsensitive]
              ) != nil else { return nil }

        let body = Data(request[separator.upperBound...].utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AgentEvent.self, from: body)
    }
}
