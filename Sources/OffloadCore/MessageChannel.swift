import Foundation
import Network

public enum OffloadService {
    public static let type = "_smartoffload._tcp"
}

public struct RequestHeader: Codable, Sendable {
    public var id: UInt64
    public var task: TaskKind?

    public init(id: UInt64, task: TaskKind?) {
        self.id = id
        self.task = task
    }
}

public struct ResponseHeader: Codable, Sendable {
    public var id: UInt64
    public var processingTime: Double
    public var inferenceEstimates: [String: Double]
    public var result: InferenceResult?
    public var error: String?

    public init(
        id: UInt64,
        processingTime: Double = 0,
        inferenceEstimates: [String: Double] = [:],
        result: InferenceResult? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.processingTime = processingTime
        self.inferenceEstimates = inferenceEstimates
        self.result = result
        self.error = error
    }
}

public struct WireMessage: Sendable {
    public var header: Data
    public var payload: Data

    public init(header: Data, payload: Data = Data()) {
        self.header = header
        self.payload = payload
    }
}

public struct ServiceEndpoint: @unchecked Sendable {
    let endpoint: NWEndpoint
}

public enum ChannelError: Error {
    case closed
    case oversized
}

public final class MessageChannel: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "smart-offload.network")
    private static let maximumHeaderBytes = 1 << 20
    private static let maximumPayloadBytes = 32 << 20

    private let connection: NWConnection

    static var parameters: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        return NWParameters(tls: nil, tcp: tcp)
    }

    init(connection: NWConnection) {
        self.connection = connection
    }

    convenience init(endpoint: ServiceEndpoint) {
        self.init(connection: NWConnection(to: endpoint.endpoint, using: Self.parameters))
    }

    func start() {
        connection.start(queue: Self.queue)
    }

    func cancel() {
        connection.cancel()
    }

    func send(_ message: WireMessage) async throws {
        var data = Data(capacity: 8 + message.header.count + message.payload.count)
        data.append(Self.encodeLength(message.header.count))
        data.append(Self.encodeLength(message.payload.count))
        data.append(message.header)
        data.append(message.payload)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func receive() async throws -> WireMessage {
        let prefix = try await receive(count: 8)
        let headerLength = Self.decodeLength(prefix.prefix(4))
        let payloadLength = Self.decodeLength(prefix.suffix(4))
        guard headerLength <= Self.maximumHeaderBytes, payloadLength <= Self.maximumPayloadBytes else {
            throw ChannelError.oversized
        }
        let header = try await receive(count: headerLength)
        let payload = try await receive(count: payloadLength)
        return WireMessage(header: header, payload: payload)
    }

    private func receive(count: Int) async throws -> Data {
        if count == 0 { return Data() }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ChannelError.closed)
                }
            }
        }
    }

    private static func encodeLength(_ length: Int) -> Data {
        withUnsafeBytes(of: UInt32(length).bigEndian) { Data($0) }
    }

    private static func decodeLength(_ data: Data) -> Int {
        Int(data.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }
}
