public struct MovingAverage: Codable, Sendable, Equatable {
    public private(set) var value: Double?
    public var smoothing: Double

    public init(smoothing: Double = 0.3) {
        self.smoothing = smoothing
    }

    public mutating func add(_ sample: Double) {
        if let current = value {
            value = current + smoothing * (sample - current)
        } else {
            value = sample
        }
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
