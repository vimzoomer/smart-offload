import Foundation
import Network

public actor WorkerDirectory {
    private var browser: NWBrowser?
    private var advertised: [String: ServiceEndpoint] = [:]
    private var links: [String: WorkerLink] = [:]

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(
            for: .bonjour(type: OffloadService.type, domain: nil),
            using: MessageChannel.parameters
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            var found: [String: ServiceEndpoint] = [:]
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint {
                    found[name] = ServiceEndpoint(endpoint: result.endpoint)
                }
            }
            let advertised = found
            Task { await self?.update(advertised) }
        }
        browser.start(queue: .global())
        self.browser = browser
        Task { await self.sweepLoop() }
    }

    public func candidates(for kind: TaskKind) async -> [WorkerCandidate] {
        var candidates: [WorkerCandidate] = []
        for link in links.values {
            if let candidate = await link.candidate(for: kind) {
                candidates.append(candidate)
            }
        }
        return candidates.sorted { $0.id < $1.id }
    }

    public func statuses() async -> [WorkerStatus] {
        var statuses: [WorkerStatus] = []
        for link in links.values {
            statuses.append(await link.status())
        }
        return statuses.sorted { $0.id < $1.id }
    }

    public func link(_ id: String) -> WorkerLink? {
        links[id]
    }

    private func update(_ found: [String: ServiceEndpoint]) async {
        advertised = found
        await reconcile()
    }

    private func sweepLoop() async {
        while true {
            try? await Task.sleep(for: .seconds(2))
            await reconcile()
        }
    }

    private func reconcile() async {
        for (name, link) in Array(links) where !(await link.isAlive) {
            if links[name] === link {
                links[name] = nil
            }
        }
        for (name, endpoint) in advertised where links[name] == nil {
            let link = WorkerLink(id: name, endpoint: endpoint)
            links[name] = link
            await link.start()
        }
    }
}
