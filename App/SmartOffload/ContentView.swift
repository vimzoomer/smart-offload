import OffloadCore
import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        @Bindable var model = model
        ZStack {
            CameraPreview(session: model.camera.session)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    Picker("Task", selection: $model.kind) {
                        Text("Objects").tag(TaskKind.objectDetection)
                        Text("Text").tag(TaskKind.textRecognition)
                    }
                    Picker("Mode", selection: $model.mode) {
                        Text("Auto").tag(OffloadMode.automatic)
                        Text("Phone").tag(OffloadMode.localOnly)
                        Text("Mac").tag(OffloadMode.remoteOnly)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                Spacer()

                StatusPanel(model: model)
            }
            .padding()
        }
        .task { await model.start() }
    }
}

private struct StatusPanel: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.cameraDenied {
                Text("Camera access denied. Enable it in Settings.")
                    .foregroundStyle(.red)
            }

            HStack {
                Text(targetTitle)
                    .font(.headline)
                Spacer()
                Text(measuredText)
                    .font(.headline.monospacedDigit())
            }

            Text(estimateText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if let error = model.lastRecord?.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()

            if model.items.isEmpty {
                Text("Nothing recognized")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.items.prefix(6).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.text)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int((item.confidence * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Divider()

            Text(signalsText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(workersText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            ShareLink("Share decision log", item: model.logURL)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var targetTitle: String {
        guard let record = model.lastRecord else { return "Waiting for frames" }
        switch record.executedTarget {
        case .local:
            return "On phone"
        case .remote(let workerID):
            return "On \(workerID)"
        }
    }

    private var measuredText: String {
        guard let duration = model.lastRecord?.measuredDuration else { return "" }
        let fps = model.framesPerSecond.value.map { String(format: " · %.1f fps", $0) } ?? ""
        return "\(milliseconds(duration))\(fps)"
    }

    private var estimateText: String {
        guard let decision = model.lastRecord?.decision else { return "Estimates: none yet" }
        var parts = ["phone \(milliseconds(decision.localCost.total))"]
        for remote in decision.remoteCosts {
            parts.append("\(remote.workerID) \(milliseconds(remote.total))")
        }
        return "Estimates: " + parts.joined(separator: " · ")
    }

    private var signalsText: String {
        let device = model.device
        var parts = [
            "Battery \(Int((device.batteryLevel * 100).rounded()))%\(device.isCharging ? " charging" : "")",
            "thermal \(thermalName(device.thermalState))",
            "CPU \(Int((device.cpuLoad * 100).rounded()))%",
            networkName(model.networkType),
        ]
        if device.isLowPowerMode {
            parts.append("low power")
        }
        if let uplink = model.status?.uplinkBitsPerSecond {
            parts.append(String(format: "uplink %.0f Mbit/s", uplink / 1_000_000))
        }
        return parts.joined(separator: " · ")
    }

    private var workersText: String {
        guard let workers = model.status?.workers, !workers.isEmpty else { return "No workers found" }
        return workers.map { worker in
            guard let roundTripTime = worker.roundTripTime else { return "\(worker.id): connecting" }
            return "\(worker.id): RTT \(milliseconds(roundTripTime))"
        }.joined(separator: " · ")
    }

    private func milliseconds(_ seconds: Double) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }

    private func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private func networkName(_ type: NetworkType) -> String {
        switch type {
        case .wifi: "Wi-Fi"
        case .cellular: "cellular"
        case .none: "offline"
        }
    }
}
