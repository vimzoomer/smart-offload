import AVFoundation
import Foundation
import Observation
import OffloadCore
import UIKit

@MainActor
@Observable
final class AppModel {
    var kind = TaskKind.objectDetection {
        didSet {
            items = []
            processor.update(kind: kind)
        }
    }

    var mode = OffloadMode.automatic {
        didSet {
            let mode = mode
            Task { await pipeline.setMode(mode) }
        }
    }

    private(set) var items: [RecognizedItem] = []
    private(set) var lastRecord: DecisionRecord?
    private(set) var framesPerSecond = MovingAverage(smoothing: 0.2)
    private(set) var device = DeviceState(batteryLevel: 1)
    private(set) var networkType = NetworkType.none
    private(set) var status: PipelineStatus?
    private(set) var cameraDenied = false

    let camera = CameraController()
    let logURL: URL

    private let directory = WorkerDirectory()
    private let networkMonitor = NetworkMonitor()
    private let cpuSampler = CPULoadSampler()
    private let pipeline: OffloadPipeline
    private let processor: FrameProcessor
    private var lastFrameAt: ContinuousClock.Instant?
    private var started = false

    init() {
        logURL = URL.documentsDirectory.appending(path: "decisions.jsonl")
        pipeline = OffloadPipeline(directory: directory, log: DecisionLog(fileURL: logURL))
        processor = FrameProcessor(pipeline: pipeline, networkMonitor: networkMonitor)
    }

    func start() async {
        guard !started else { return }
        started = true

        UIDevice.current.isBatteryMonitoringEnabled = true
        UIApplication.shared.isIdleTimerDisabled = true
        networkMonitor.start()
        await directory.start()
        refreshSignals()
        Task {
            while true {
                try? await Task.sleep(for: .seconds(1))
                refreshSignals()
                status = await pipeline.status()
            }
        }

        await pipeline.warmUp()
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            cameraDenied = true
            return
        }
        processor.onOutcome = { [weak self] outcome in
            self?.apply(outcome)
        }
        let processor = self.processor
        camera.onFrame = { buffer in
            processor.handle(buffer)
        }
        camera.start()
    }

    private func apply(_ outcome: FrameOutcome) {
        let now = ContinuousClock.now
        if let lastFrameAt {
            let interval = now - lastFrameAt
            let seconds = Double(interval.components.seconds) + Double(interval.components.attoseconds) * 1e-18
            if seconds > 0 {
                framesPerSecond.add(1 / seconds)
            }
        }
        lastFrameAt = now
        lastRecord = outcome.record
        if outcome.record.inputs.task.kind == kind, let result = outcome.result {
            items = result.items
        }
    }

    private func refreshSignals() {
        let level = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        device = DeviceState(
            batteryLevel: level < 0 ? 1 : Double(level),
            isCharging: batteryState == .charging || batteryState == .full,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState,
            cpuLoad: cpuSampler.sample()
        )
        networkType = networkMonitor.current
        processor.update(device: device)
    }
}
