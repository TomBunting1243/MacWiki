#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO

private enum ComparisonError: LocalizedError {
    case usage
    case unreadable(String)
    case dimensionMismatch(CGSize, CGSize)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: compare_images.swift <first image> <second image>"
        case .unreadable(let path):
            "Could not decode image: \(path)"
        case .dimensionMismatch(let first, let second):
            "Image dimensions differ: \(first) versus \(second)"
        }
    }
}

private struct ComparisonResult: Codable {
    let width: Int
    let height: Int
    let changedPixels: Int
    let changedPixelRatio: Double
    let maximumChannelDelta: Int
}

private func decodeRGBA(path: String) throws -> (image: CGImage, pixels: [UInt8]) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ComparisonError.unreadable(path)
    }

    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    guard let context = CGContext(
        data: &pixels,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw ComparisonError.unreadable(path)
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return (image, pixels)
}

do {
    guard CommandLine.arguments.count == 3 else { throw ComparisonError.usage }
    let first = try decodeRGBA(path: CommandLine.arguments[1])
    let second = try decodeRGBA(path: CommandLine.arguments[2])
    guard first.image.width == second.image.width,
          first.image.height == second.image.height else {
        throw ComparisonError.dimensionMismatch(
            CGSize(width: first.image.width, height: first.image.height),
            CGSize(width: second.image.width, height: second.image.height)
        )
    }

    var changedPixels = 0
    var maximumChannelDelta = 0
    for pixelOffset in stride(from: 0, to: first.pixels.count, by: 4) {
        var pixelChanged = false
        for channelOffset in 0..<3 {
            let delta = abs(
                Int(first.pixels[pixelOffset + channelOffset]) -
                Int(second.pixels[pixelOffset + channelOffset])
            )
            maximumChannelDelta = max(maximumChannelDelta, delta)
            pixelChanged = pixelChanged || delta > 1
        }
        if pixelChanged { changedPixels += 1 }
    }

    let totalPixels = first.image.width * first.image.height
    let result = ComparisonResult(
        width: first.image.width,
        height: first.image.height,
        changedPixels: changedPixels,
        changedPixelRatio: Double(changedPixels) / Double(totalPixels),
        maximumChannelDelta: maximumChannelDelta
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))

    if changedPixels < 100 || maximumChannelDelta < 2 {
        exit(1)
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
