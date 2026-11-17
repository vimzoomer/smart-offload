import Foundation

public struct Frame: Sendable {
    public var kind: TaskKind
    public var jpeg: Data
    public var pixelBuffer: PixelBuffer?

    public init(kind: TaskKind, jpeg: Data, pixelBuffer: PixelBuffer? = nil) {
        self.kind = kind
        self.jpeg = jpeg
        self.pixelBuffer = pixelBuffer
    }
}

public struct FrameOutcome: Sendable {
    public var result: InferenceResult?
    public var record: DecisionRecord
}

public struct PipelineStatus: Sendable {
    public var localEstimates: [TaskKind: Double]
    public var uplinkBitsPerSecond: Double?
    public var workers: [WorkerStatus]
}

public actor OffloadPipeline {
    public struct Configuration: Sendable {
        public var probeInterval: Double
        public var assumedUplinkBitsPerSecond: Double
        public var assumedLocalInferenceTime: Double

        public init(
            probeInterval: Double = 5,
            assumedUplinkBitsPerSecond: Double = 20_000_000,
            assumedLocalInferenceTime: Double = 0.1
        ) {
            self.probeInterval = probeInterval
            self.assumedUplinkBitsPerSecond = assumedUplinkBitsPerSecond
            self.assumedLocalInferenceTime = assumedLocalInferenceTime
        }
    }

    private struct ProbeKey: Hashable {
        var target: OffloadTarget
        var kind: TaskKind
    }

    private struct Execution {
        var result: InferenceResult?
        var duration: Double?
        var remoteProcessingTime: Double?
        var error: String?
    }

    private let engine: DecisionEngine
    private let directory: WorkerDirectory
    private let log: DecisionLog?
    private let configuration: Configuration
    private let runner = InferenceRunner()

    private var mode = OffloadMode.automatic
    private var localEstimates: [TaskKind: MovingAverage] = [:]
    private var uplink = MovingAverage()
    private var previousTargets: [TaskKind: OffloadTarget] = [:]
    private var lastMeasured: [ProbeKey: ContinuousClock.Instant] = [:]
    private var probesInFlight: Set<ProbeKey> = []

    public init(
        engine: DecisionEngine = DecisionEngine(),
        directory: WorkerDirectory,
        log: DecisionLog? = nil,
        configuration: Configuration = Configuration()
    ) {
        self.engine = engine
        self.directory = directory
        self.log = log
        self.configuration = configuration
    }

    public func setMode(_ mode: OffloadMode) {
        self.mode = mode
    }

    public func warmUp() async {
        guard let frame = SyntheticFrame.jpeg() else { return }
        for kind in TaskKind.allCases {
            _ = try? await runner.run(kind, on: .jpeg(frame))
        }
    }

    public func status() async -> PipelineStatus {
        PipelineStatus(
            localEstimates: localEstimates.compactMapValues(\.value),
            uplinkBitsPerSecond: uplink.value,
            workers: await directory.statuses()
        )
    }

    public func process(_ frame: Frame, device: DeviceState, networkType: NetworkType) async -> FrameOutcome {
        let workers = await directory.candidates(for: frame.kind)
        let inputs = DecisionInputs(
            task: FrameTask(kind: frame.kind, payloadBytes: frame.jpeg.count),
            predictedLocalInferenceTime: localEstimates[frame.kind]?.value ?? configuration.assumedLocalInferenceTime,
            device: device,
            network: NetworkState(
                type: networkType,
                uplinkBitsPerSecond: uplink.value ?? configuration.assumedUplinkBitsPerSecond
            ),
            workers: workers
        )
        let mode = self.mode
        let decision = engine.decide(inputs, previous: previousTargets[frame.kind])

        var target = chosenTarget(for: decision, kind: frame.kind, mode: mode)
        var execution = await execute(target, frame: frame, workers: workers)
        if execution.result == nil, target != .local {
            let remoteError = execution.error
            target = .local
            execution = await execute(.local, frame: frame, workers: workers)
            execution.error = execution.error ?? remoteError
        }

        if mode == .automatic {
            previousTargets[frame.kind] = target
            startProbes(excluding: target, frame: frame, workers: workers, inputs: inputs, decision: decision)
        }

        let record = makeRecord(
            mode: mode, inputs: inputs, decision: decision, target: target, isProbe: false, execution: execution
        )
        await log?.append(record)
        return FrameOutcome(result: execution.result, record: record)
    }

    private func chosenTarget(for decision: Decision, kind: TaskKind, mode: OffloadMode) -> OffloadTarget {
        switch mode {
        case .localOnly:
            return .local
        case .remoteOnly:
            guard let cheapest = decision.remoteCosts.min(by: { $0.total < $1.total }) else { return .local }
            return .remote(workerID: cheapest.workerID)
        case .automatic:
            return localEstimates[kind]?.value == nil ? .local : decision.target
        }
    }

    private func execute(_ target: OffloadTarget, frame: Frame, workers: [WorkerCandidate]) async -> Execution {
        let key = ProbeKey(target: target, kind: frame.kind)
        switch target {
        case .local:
            do {
                let image = frame.pixelBuffer.map(InferenceImage.pixelBuffer) ?? .jpeg(frame.jpeg)
                let timed = try await runner.run(frame.kind, on: image)
                localEstimates[frame.kind, default: MovingAverage()].add(timed.duration)
                lastMeasured[key] = .now
                return Execution(result: timed.result, duration: timed.duration)
            } catch {
                return Execution(error: String(describing: error))
            }
        case .remote(let workerID):
            guard let link = await directory.link(workerID) else {
                return Execution(error: "worker unavailable")
            }
            do {
                let remote = try await link.infer(frame.kind, jpeg: frame.jpeg)
                let roundTripTime = workers.first { $0.id == workerID }?.roundTripTime ?? 0
                let transferTime = max(remote.elapsed - remote.processingTime - roundTripTime, 0.0005)
                uplink.add(min(Double(frame.jpeg.count) * 8 / transferTime, 1_000_000_000))
                lastMeasured[key] = .now
                return Execution(
                    result: remote.result,
                    duration: remote.elapsed,
                    remoteProcessingTime: remote.processingTime
                )
            } catch {
                return Execution(error: String(describing: error))
            }
        }
    }

    private func startProbes(
        excluding executed: OffloadTarget,
        frame: Frame,
        workers: [WorkerCandidate],
        inputs: DecisionInputs,
        decision: Decision
    ) {
        let now = ContinuousClock.now
        let alternatives = [OffloadTarget.local] + workers.map { OffloadTarget.remote(workerID: $0.id) }
        for target in alternatives where target != executed {
            let key = ProbeKey(target: target, kind: frame.kind)
            if probesInFlight.contains(key) { continue }
            if let last = lastMeasured[key], (now - last).seconds < configuration.probeInterval { continue }
            probesInFlight.insert(key)
            lastMeasured[key] = now
            Task {
                let execution = await self.execute(target, frame: frame, workers: workers)
                self.probesInFlight.remove(key)
                let record = self.makeRecord(
                    mode: .automatic, inputs: inputs, decision: decision, target: target, isProbe: true,
                    execution: execution
                )
                await self.log?.append(record)
            }
        }
    }

    private func makeRecord(
        mode: OffloadMode,
        inputs: DecisionInputs,
        decision: Decision,
        target: OffloadTarget,
        isProbe: Bool,
        execution: Execution
    ) -> DecisionRecord {
        DecisionRecord(
            timestamp: Date(),
            mode: mode,
            inputs: inputs,
            decision: decision,
            executedTarget: target,
            isProbe: isProbe,
            measuredDuration: execution.duration,
            remoteProcessingTime: execution.remoteProcessingTime,
            error: execution.error
        )
    }
}
