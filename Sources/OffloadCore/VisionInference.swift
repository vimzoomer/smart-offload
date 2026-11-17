import CoreVideo
import Foundation
import Vision

public struct RecognizedItem: Codable, Sendable, Equatable {
    public var text: String
    public var confidence: Double

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
    }
}

public struct InferenceResult: Codable, Sendable, Equatable {
    public var kind: TaskKind
    public var items: [RecognizedItem]

    public init(kind: TaskKind, items: [RecognizedItem]) {
        self.kind = kind
        self.items = items
    }
}

public struct PixelBuffer: @unchecked Sendable {
    public let buffer: CVPixelBuffer

    public init(_ buffer: CVPixelBuffer) {
        self.buffer = buffer
    }
}

public enum InferenceImage: Sendable {
    case jpeg(Data)
    case pixelBuffer(PixelBuffer)
}

public enum VisionInference {
    public static func run(_ kind: TaskKind, on image: InferenceImage) throws -> InferenceResult {
        let handler: VNImageRequestHandler
        switch image {
        case .jpeg(let data):
            handler = VNImageRequestHandler(data: data, options: [:])
        case .pixelBuffer(let pixelBuffer):
            handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer.buffer, options: [:])
        }

        switch kind {
        case .objectDetection:
            let request = VNClassifyImageRequest()
            try handler.perform([request])
            let items = (request.results ?? [])
                .filter { $0.confidence >= 0.1 }
                .sorted { $0.confidence > $1.confidence }
                .prefix(5)
                .map { RecognizedItem(text: $0.identifier, confidence: Double($0.confidence)) }
            return InferenceResult(kind: kind, items: Array(items))
        case .textRecognition:
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try handler.perform([request])
            let items = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first }
                .map { RecognizedItem(text: $0.string, confidence: Double($0.confidence)) }
            return InferenceResult(kind: kind, items: items)
        }
    }
}

public struct TimedInference: Sendable {
    public var result: InferenceResult
    public var duration: Double
}

public final class InferenceRunner: Sendable {
    private let queue = DispatchQueue(label: "smart-offload.inference", qos: .userInitiated)

    public init() {}

    public func run(_ kind: TaskKind, on image: InferenceImage) async throws -> TimedInference {
        let start = ContinuousClock.now
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try VisionInference.run(kind, on: image)
                    let duration = (ContinuousClock.now - start).seconds
                    continuation.resume(returning: TimedInference(result: result, duration: duration))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
