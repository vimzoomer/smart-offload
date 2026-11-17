import Foundation
import OffloadCore

setvbuf(stdout, nil, _IOLBF, 0)

let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

do {
    let server = try WorkerServer(name: name) { message in
        print(message)
    }
    print("offload-worker \(OffloadCore.version) advertising \"\(name)\" as \(OffloadService.type)")
    server.start()
    Task { await server.warmUp() }
    dispatchMain()
} catch {
    print("failed to start worker: \(error)")
    exit(1)
}
