#!/usr/bin/swift

import AppKit
import Foundation
import Vision

private func usage() {
    let text = """
    Usage:
      ocr_text.swift <image-path>
    """
    fputs(text + "\n", stderr)
}

guard CommandLine.arguments.count == 2 else {
    usage()
    exit(64)
}

let imagePath = CommandLine.arguments[1]
let imageURL = URL(fileURLWithPath: imagePath)

guard let image = NSImage(contentsOf: imageURL) else {
    fputs("ERROR: Unable to load image: \(imagePath)\n", stderr)
    exit(1)
}

guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("ERROR: Unable to convert image to CGImage: \(imagePath)\n", stderr)
    exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    fputs("ERROR: OCR failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

let text = (request.results ?? [])
    .compactMap { $0.topCandidates(1).first?.string }
    .joined(separator: "\n")

print(text)
