import CoreImage
import CoreVideo
import Foundation
import OffloadCore
import os

final class FrameProcessor: @unchecked Sendable {
    private struct State {
        var kind = TaskKind.objectDetection
        var device = DeviceState(batteryLevel: 1)
        var isBusy = false
    }

    var onOutcome: (@MainActor (FrameOutcome) -> Void)?

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let context = CIContext()
    private let pipeline: OffloadPipeline
    private let networkMonitor: NetworkMonitor

    init(pipeline: OffloadPipeline, networkMonitor: NetworkMonitor) {
        self.pipeline = pipeline
        self.networkMonitor = networkMonitor
    }

    func update(kind: TaskKind) {
        state.withLock { $0.kind = kind }
    }

    func update(device: DeviceState) {
        state.withLock { $0.device = device }
    }

    func handle(_ buffer: CVPixelBuffer) {
        let claimed: State? = state.withLock { state in
            if state.isBusy { return nil }
            state.isBusy = true
            return state
        }
        guard let claimed else { return }

        let options = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.7]
        guard let jpeg = context.jpegRepresentation(
            of: CIImage(cvPixelBuffer: buffer),
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: options
        ) else {
            state.withLock { $0.isBusy = false }
            return
        }

        let frame = Frame(kind: claimed.kind, jpeg: jpeg, pixelBuffer: PixelBuffer(buffer))
        let networkType = networkMonitor.current
        Task {
            let outcome = await pipeline.process(frame, device: claimed.device, networkType: networkType)
            state.withLock { $0.isBusy = false }
            await onOutcome?(outcome)
        }
    }
}
