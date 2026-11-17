import Foundation
import Network
import os

public final class WorkerServer: @unchecked Sendable {
    private let listener: NWListener
    private let runner = InferenceRunner()
    private let estimates = OSAllocatedUnfairLock<[TaskKind: MovingAverage]>(initialState: [:])
    private let log: @Sendable (String) -> Void

    public init(name: String, log: @escaping @Sendable (String) -> Void = { _ in }) throws {
        self.log = log
        listener = try NWListener(using: MessageChannel.parameters)
        listener.service = NWListener.Service(name: name, type: OffloadService.type)
    }

    public func start() {
        let log = self.log
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                log("listening on port \(self?.listener.port?.rawValue ?? 0)")
            case .failed(let error):
                log("listener failed: \(error)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            log("client connected: \(connection.endpoint)")
            let channel = MessageChannel(connection: connection)
            channel.start()
            Task { await self.serve(channel) }
        }
        listener.start(queue: .global())
    }

    public func warmUp() async {
        guard let frame = SyntheticFrame.jpeg() else { return }
        for kind in TaskKind.allCases {
            _ = try? await runner.run(kind, on: .jpeg(frame))
            if let timed = try? await runner.run(kind, on: .jpeg(frame)) {
                record(timed.duration, for: kind)
                log("warm-up \(kind.rawValue): \(Self.milliseconds(timed.duration))")
            }
        }
    }

    private func serve(_ channel: MessageChannel) async {
        do {
            while true {
                let message = try await channel.receive()
                let request = try JSONDecoder().decode(RequestHeader.self, from: message.header)
                Task { await self.respond(to: request, payload: message.payload, on: channel) }
            }
        } catch {
            log("client disconnected")
            channel.cancel()
        }
    }

    private func respond(to request: RequestHeader, payload: Data, on channel: MessageChannel) async {
        var response = ResponseHeader(id: request.id)
        if let kind = request.task {
            do {
                let timed = try await runner.run(kind, on: .jpeg(payload))
                record(timed.duration, for: kind)
                response.result = timed.result
                response.processingTime = timed.duration
                log("\(kind.rawValue) \(payload.count / 1024) KB in \(Self.milliseconds(timed.duration))")
            } catch {
                response.error = String(describing: error)
                log("\(kind.rawValue) failed: \(error)")
            }
        }
        response.inferenceEstimates = estimates.withLock { current in
            var reported: [String: Double] = [:]
            for (kind, average) in current {
                reported[kind.rawValue] = average.value
            }
            return reported
        }
        guard let header = try? JSONEncoder().encode(response) else { return }
        try? await channel.send(WireMessage(header: header))
    }

    private func record(_ duration: Double, for kind: TaskKind) {
        estimates.withLock { $0[kind, default: MovingAverage()].add(duration) }
    }

    private static func milliseconds(_ seconds: Double) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }
}
