#!/usr/bin/swift

import AppKit
import Foundation
import Vision

private func usage() {
    let text = """
    Usage:
      ocr_find_text_centers.swift <image-path> <query>
    """
    fputs(text + "\n", stderr)
}

guard CommandLine.arguments.count >= 3 else {
    usage()
    exit(64)
}

let imagePath = CommandLine.arguments[1]
let query = CommandLine.arguments[2...].joined(separator: " ").lowercased()
let imageURL = URL(fileURLWithPath: imagePath)

guard let image = NSImage(contentsOf: imageURL),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("ERROR: Unable to load image: \(imagePath)\n", stderr)
    exit(1)
}

let width = Double(cgImage.width)
let height = Double(cgImage.height)

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

struct Hit {
    let x: Int
    let y: Int
    let text: String
}

var hits: [Hit] = []
for observation in request.results ?? [] {
    guard let candidate = observation.topCandidates(1).first else { continue }
    let text = candidate.string
    guard text.lowercased().contains(query) else { continue }

    let box = observation.boundingBox
    let centerX = Int(((box.origin.x + box.size.width / 2.0) * width).rounded())
    let centerY = Int(((1.0 - (box.origin.y + box.size.height / 2.0)) * height).rounded())
    hits.append(Hit(x: centerX, y: centerY, text: text))
}

hits.sort {
    if $0.y == $1.y { return $0.x < $1.x }
    return $0.y < $1.y
}

for hit in hits {
    print("\(hit.x),\(hit.y),\(hit.text)")
}
