import Darwin
import Foundation
import Network
import os

public final class NetworkMonitor: Sendable {
    private let monitor = NWPathMonitor()
    private let state = OSAllocatedUnfairLock<NetworkType>(initialState: .none)

    public init() {}

    public var current: NetworkType {
        state.withLock { $0 }
    }

    public func start() {
        let state = self.state
        monitor.pathUpdateHandler = { path in
            let type: NetworkType
            if path.status != .satisfied {
                type = .none
            } else if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                type = .wifi
            } else if path.usesInterfaceType(.cellular) {
                type = .cellular
            } else {
                type = .none
            }
            state.withLock { $0 = type }
        }
        monitor.start(queue: .global())
    }
}

public final class CPULoadSampler: Sendable {
    private struct Ticks: Sendable {
        var busy: UInt32
        var idle: UInt32
    }

    private let previous = OSAllocatedUnfairLock<Ticks?>(initialState: nil)

    public init() {}

    public func sample() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }

        let ticks = Ticks(
            busy: info.cpu_ticks.0 &+ info.cpu_ticks.1 &+ info.cpu_ticks.3,
            idle: info.cpu_ticks.2
        )
        return previous.withLock { last in
            defer { last = ticks }
            guard let last else { return 0 }
            let busy = Double(ticks.busy &- last.busy)
            let idle = Double(ticks.idle &- last.idle)
            return busy + idle > 0 ? busy / (busy + idle) : 0
        }
    }
}
