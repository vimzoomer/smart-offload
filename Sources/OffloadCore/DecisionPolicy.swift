import Foundation

public struct ThermalSlowdown: Codable, Sendable, Equatable {
    public var nominal: Double
    public var fair: Double
    public var serious: Double
    public var critical: Double

    public init(nominal: Double = 1.0, fair: Double = 1.1, serious: Double = 1.5, critical: Double = 3.0) {
        self.nominal = nominal
        self.fair = fair
        self.serious = serious
        self.critical = critical
    }

    public func multiplier(for state: ProcessInfo.ThermalState) -> Double {
        switch state {
        case .nominal: nominal
        case .fair: fair
        case .serious: serious
        case .critical: critical
        @unknown default: critical
        }
    }
}

public struct DecisionPolicy: Codable, Sendable, Equatable {
    public var lowBatteryThreshold: Double
    public var lowBatteryPenalty: Double
    public var lowPowerModePenalty: Double
    public var cpuLoadWeight: Double
    public var thermalSlowdown: ThermalSlowdown
    public var switchMargin: Double

    public init(
        lowBatteryThreshold: Double = 0.2,
        lowBatteryPenalty: Double = 2.0,
        lowPowerModePenalty: Double = 0.5,
        cpuLoadWeight: Double = 1.0,
        thermalSlowdown: ThermalSlowdown = ThermalSlowdown(),
        switchMargin: Double = 0.1
    ) {
        self.lowBatteryThreshold = lowBatteryThreshold
        self.lowBatteryPenalty = lowBatteryPenalty
        self.lowPowerModePenalty = lowPowerModePenalty
        self.cpuLoadWeight = cpuLoadWeight
        self.thermalSlowdown = thermalSlowdown
        self.switchMargin = switchMargin
    }
}
