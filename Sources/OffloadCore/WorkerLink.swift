import Foundation

public struct RemoteInference: Sendable {
    public var result: InferenceResult
    public var processingTime: Double
    public var elapsed: Double
}

public struct WorkerStatus: Sendable, Equatable, Identifiable {
    public var id: String
    public var roundTripTime: Double?
    public var inferenceEstimates: [TaskKind: Double]
}

public enum WorkerLinkError: Error {
    case timeout
    case disconnected
    case malformedResponse
    case remote(String)
}

public actor WorkerLink {
    public nonisolated let id: String

    private struct Reply {
        var header: ResponseHeader
        var elapsed: Double
    }

    private struct Pending {
        var continuation: CheckedContinuation<Reply, Error>
        var sentAt: ContinuousClock.Instant
    }

    private let channel: MessageChannel
    private var pending: [UInt64: Pending] = [:]
    private var nextRequestID: UInt64 = 0
    private var roundTripTime = MovingAverage()
    private var inferenceEstimates: [TaskKind: Double] = [:]
    private var missedPings = 0
    public private(set) var isAlive = true

    init(id: String, endpoint: ServiceEndpoint) {
        self.id = id
        channel = MessageChannel(endpoint: endpoint)
    }

    func start() {
        channel.start()
        Task { await self.receiveLoop() }
        Task { await self.pingLoop() }
    }

    func stop() {
        shutdown()
    }

    public func infer(_ kind: TaskKind, jpeg: Data) async throws -> RemoteInference {
        let reply = try await request(task: kind, payload: jpeg, timeout: .seconds(3))
        if let error = reply.header.error {
            throw WorkerLinkError.remote(error)
        }
        guard let result = reply.header.result else {
            throw WorkerLinkError.malformedResponse
        }
        return RemoteInference(result: result, processingTime: reply.header.processingTime, elapsed: reply.elapsed)
    }

    public func status() -> WorkerStatus {
        WorkerStatus(id: id, roundTripTime: roundTripTime.value, inferenceEstimates: inferenceEstimates)
    }

    func candidate(for kind: TaskKind) -> WorkerCandidate? {
        guard isAlive, let rtt = roundTripTime.value, let estimate = inferenceEstimates[kind] else { return nil }
        return WorkerCandidate(id: id, roundTripTime: rtt, predictedInferenceTime: estimate)
    }

    private func request(task: TaskKind?, payload: Data, timeout: Duration) async throws -> Reply {
        guard isAlive else { throw WorkerLinkError.disconnected }
        nextRequestID += 1
        let id = nextRequestID
        let header = try JSONEncoder().encode(RequestHeader(id: id, task: task))
        let channel = self.channel
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = Pending(continuation: continuation, sentAt: .now)
            Task {
                do {
                    try await channel.send(WireMessage(header: header, payload: payload))
                } catch {
                    self.fail(id, with: error)
                }
            }
            Task {
                try? await Task.sleep(for: timeout)
                self.fail(id, with: WorkerLinkError.timeout)
            }
        }
    }

    private func fail(_ id: UInt64, with error: Error) {
        pending.removeValue(forKey: id)?.continuation.resume(throwing: error)
    }

    private func deliver(_ header: ResponseHeader, receivedAt: ContinuousClock.Instant) {
        for (name, estimate) in header.inferenceEstimates {
            if let kind = TaskKind(rawValue: name) {
                inferenceEstimates[kind] = estimate
            }
        }
        guard let entry = pending.removeValue(forKey: header.id) else { return }
        entry.continuation.resume(returning: Reply(header: header, elapsed: (receivedAt - entry.sentAt).seconds))
    }

    private func receiveLoop() async {
        while isAlive {
            do {
                let message = try await channel.receive()
                let receivedAt = ContinuousClock.now
                let header = try JSONDecoder().decode(ResponseHeader.self, from: message.header)
                deliver(header, receivedAt: receivedAt)
            } catch {
                shutdown()
            }
        }
    }

    private func pingLoop() async {
        while isAlive {
            do {
                let reply = try await request(task: nil, payload: Data(), timeout: .seconds(2))
                roundTripTime.add(max(reply.elapsed - reply.header.processingTime, 0))
                missedPings = 0
            } catch {
                missedPings += 1
                if missedPings >= 3 {
                    shutdown()
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func shutdown() {
        guard isAlive else { return }
        isAlive = false
        channel.cancel()
        let waiting = pending.values
        pending.removeAll()
        for entry in waiting {
            entry.continuation.resume(throwing: WorkerLinkError.disconnected)
        }
    }
}
