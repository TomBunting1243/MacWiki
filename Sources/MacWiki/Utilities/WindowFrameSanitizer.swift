import CoreGraphics
import Foundation

enum WindowFrameSanitizer {
    private static let minimumDimension: CGFloat = 120
    private static let maximumSizeMultiple: CGFloat = 3
    private static let offscreenLeeway: CGFloat = 160

    static func shouldDiscardAutosavedWindowFrame(_ value: Any?, availableFrames: [CGRect]) -> Bool {
        guard let frameString = value as? String else { return true }
        return isSerializedFrameObviouslyInvalid(frameString, availableFrames: availableFrames)
    }

    static func isSerializedFrameObviouslyInvalid(_ frameString: String, availableFrames: [CGRect]) -> Bool {
        let numbers = numericComponents(in: frameString)
        guard numbers.count >= 4 else { return true }

        let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width >= minimumDimension,
              rect.height >= minimumDimension else {
            return true
        }

        let referenceFrames = availableFrames.isEmpty
            ? [CGRect(x: 0, y: 0, width: 1440, height: 900)]
            : availableFrames
        let maxAllowedWidth = referenceFrames.map(\.width).max() ?? 1440
        let maxAllowedHeight = referenceFrames.map(\.height).max() ?? 900
        guard rect.width <= maxAllowedWidth * maximumSizeMultiple,
              rect.height <= maxAllowedHeight * maximumSizeMultiple else {
            return true
        }

        let paddedFrames = referenceFrames.map { frame in
            frame.insetBy(dx: -offscreenLeeway, dy: -offscreenLeeway)
        }
        return !paddedFrames.contains { $0.intersects(rect) }
    }

    private static func numericComponents(in string: String) -> [CGFloat] {
        let tokens = string.split { character in
            !"-+.0123456789".contains(character)
        }
        return tokens.compactMap { token in
            guard let value = Double(token) else { return nil }
            return CGFloat(value)
        }
    }
}
