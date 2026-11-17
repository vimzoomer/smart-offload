import Foundation

public enum OffloadMode: String, Codable, Sendable, CaseIterable {
    case automatic
    case localOnly
    case remoteOnly
}

public struct DecisionRecord: Codable, Sendable {
    public var timestamp: Date
    public var mode: OffloadMode
    public var inputs: DecisionInputs
    public var decision: Decision
    public var executedTarget: OffloadTarget
    public var isProbe: Bool
    public var measuredDuration: Double?
    public var remoteProcessingTime: Double?
    public var error: String?
}

public actor DecisionLog {
    public nonisolated let fileURL: URL
    private var handle: FileHandle?
    private let encoder: JSONEncoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    public func append(_ record: DecisionRecord) {
        guard var line = try? encoder.encode(record) else { return }
        line.append(0x0A)
        if handle == nil {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: fileURL)
            _ = try? handle?.seekToEnd()
        }
        try? handle?.write(contentsOf: line)
    }
}
