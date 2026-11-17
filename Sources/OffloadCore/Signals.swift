import Foundation

public enum TaskKind: String, Codable, Sendable, Hashable, CaseIterable {
    case objectDetection
    case textRecognition
}

extension ProcessInfo.ThermalState: @retroactive Codable {}

public struct DeviceState: Codable, Sendable, Equatable {
    public var batteryLevel: Double
    public var isCharging: Bool
    public var isLowPowerMode: Bool
    public var thermalState: ProcessInfo.ThermalState
    public var cpuLoad: Double

    public init(
        batteryLevel: Double,
        isCharging: Bool = false,
        isLowPowerMode: Bool = false,
        thermalState: ProcessInfo.ThermalState = .nominal,
        cpuLoad: Double = 0
    ) {
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.isLowPowerMode = isLowPowerMode
        self.thermalState = thermalState
        self.cpuLoad = cpuLoad
    }
}

public enum NetworkType: String, Codable, Sendable, Hashable, CaseIterable {
    case wifi
    case cellular
    case none
}

public struct NetworkState: Codable, Sendable, Equatable {
    public var type: NetworkType
    public var uplinkBitsPerSecond: Double

    public init(type: NetworkType, uplinkBitsPerSecond: Double) {
        self.type = type
        self.uplinkBitsPerSecond = uplinkBitsPerSecond
    }
}

public struct WorkerCandidate: Codable, Sendable, Equatable {
    public var id: String
    public var roundTripTime: Double
    public var predictedInferenceTime: Double

    public init(id: String, roundTripTime: Double, predictedInferenceTime: Double) {
        self.id = id
        self.roundTripTime = roundTripTime
        self.predictedInferenceTime = predictedInferenceTime
    }
}

public struct FrameTask: Codable, Sendable, Equatable {
    public var kind: TaskKind
    public var payloadBytes: Int

    public init(kind: TaskKind, payloadBytes: Int) {
        self.kind = kind
        self.payloadBytes = payloadBytes
    }
}

public struct DecisionInputs: Codable, Sendable, Equatable {
    public var task: FrameTask
    public var predictedLocalInferenceTime: Double
    public var device: DeviceState
    public var network: NetworkState
    public var workers: [WorkerCandidate]

    public init(
        task: FrameTask,
        predictedLocalInferenceTime: Double,
        device: DeviceState,
        network: NetworkState,
        workers: [WorkerCandidate]
    ) {
        self.task = task
        self.predictedLocalInferenceTime = predictedLocalInferenceTime
        self.device = device
        self.network = network
        self.workers = workers
    }
}
