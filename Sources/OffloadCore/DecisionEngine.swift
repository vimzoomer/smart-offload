public enum OffloadTarget: Codable, Sendable, Hashable {
    case local
    case remote(workerID: String)
}

public struct LocalCost: Codable, Sendable, Equatable {
    public var inferenceTime: Double
    public var energyPenalty: Double

    public var total: Double { inferenceTime + energyPenalty }

    public init(inferenceTime: Double, energyPenalty: Double) {
        self.inferenceTime = inferenceTime
        self.energyPenalty = energyPenalty
    }
}

public struct RemoteCost: Codable, Sendable, Equatable {
    public var workerID: String
    public var transferTime: Double
    public var roundTripTime: Double
    public var inferenceTime: Double

    public var total: Double { transferTime + roundTripTime + inferenceTime }

    public init(workerID: String, transferTime: Double, roundTripTime: Double, inferenceTime: Double) {
        self.workerID = workerID
        self.transferTime = transferTime
        self.roundTripTime = roundTripTime
        self.inferenceTime = inferenceTime
    }
}

public struct Decision: Codable, Sendable, Equatable {
    public var target: OffloadTarget
    public var estimatedCost: Double
    public var localCost: LocalCost
    public var remoteCosts: [RemoteCost]

    public init(target: OffloadTarget, estimatedCost: Double, localCost: LocalCost, remoteCosts: [RemoteCost]) {
        self.target = target
        self.estimatedCost = estimatedCost
        self.localCost = localCost
        self.remoteCosts = remoteCosts
    }
}

public struct DecisionEngine: Sendable {
    public var policy: DecisionPolicy

    public init(policy: DecisionPolicy = DecisionPolicy()) {
        self.policy = policy
    }

    public func decide(_ inputs: DecisionInputs, previous: OffloadTarget? = nil) -> Decision {
        let local = localCost(inputs)
        let remotes = remoteCosts(inputs)

        var candidates: [(target: OffloadTarget, cost: Double)] = [(.local, local.total)]
        candidates += remotes.map { (.remote(workerID: $0.workerID), $0.total) }

        var best = candidates[0]
        for candidate in candidates.dropFirst() where candidate.cost < best.cost {
            best = candidate
        }

        if let previous,
           previous != best.target,
           let kept = candidates.first(where: { $0.target == previous }),
           kept.cost <= best.cost * (1 + policy.switchMargin) {
            best = kept
        }

        return Decision(target: best.target, estimatedCost: best.cost, localCost: local, remoteCosts: remotes)
    }

    public func remoteCosts(_ inputs: DecisionInputs) -> [RemoteCost] {
        guard inputs.network.type == .wifi, inputs.network.uplinkBitsPerSecond > 0 else { return [] }
        let transferTime = Double(inputs.task.payloadBytes) * 8 / inputs.network.uplinkBitsPerSecond
        return inputs.workers.map {
            RemoteCost(
                workerID: $0.id,
                transferTime: transferTime,
                roundTripTime: $0.roundTripTime,
                inferenceTime: $0.predictedInferenceTime
            )
        }
    }

    public func localCost(_ inputs: DecisionInputs) -> LocalCost {
        let cpuLoad = min(max(inputs.device.cpuLoad, 0), 1)
        let slowdown = policy.thermalSlowdown.multiplier(for: inputs.device.thermalState)
            * (1 + policy.cpuLoadWeight * cpuLoad)
        let inferenceTime = inputs.predictedLocalInferenceTime * slowdown
        return LocalCost(
            inferenceTime: inferenceTime,
            energyPenalty: inferenceTime * energyPenaltyFactor(inputs.device)
        )
    }

    func energyPenaltyFactor(_ device: DeviceState) -> Double {
        if device.isCharging { return 0 }
        var factor = 0.0
        if device.isLowPowerMode {
            factor += policy.lowPowerModePenalty
        }
        let level = min(max(device.batteryLevel, 0), 1)
        if policy.lowBatteryThreshold > 0, level < policy.lowBatteryThreshold {
            factor += policy.lowBatteryPenalty * (policy.lowBatteryThreshold - level) / policy.lowBatteryThreshold
        }
        return factor
    }
}
