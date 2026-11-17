import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum SyntheticFrame {
    public static func jpeg(width: Int = 1280, height: Int = 720, text: String = "smart offload 12345") -> Data? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica" as CFString, 72, nil)
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes) else { return nil }
        context.textPosition = CGPoint(x: 80, y: height / 2)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
