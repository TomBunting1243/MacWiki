#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES_DIR="$ROOT_DIR/Sources/MacWiki/Resources"
OUT_PNG="$RESOURCES_DIR/AppIcon.png"
ICONSET_DIR="$(mktemp -d /tmp/macwiki-iconset-XXXXXX.iconset)"
OUT_ICNS="$RESOURCES_DIR/AppIcon.icns"
CUSTOM_SOURCE="${1:-}"

mkdir -p "$RESOURCES_DIR"

TMP_SWIFT="$(mktemp /tmp/macwiki-icon-XXXXXX.swift)"
cleanup() {
  rm -f "$TMP_SWIFT"
  rm -rf "$ICONSET_DIR"
}
trap cleanup EXIT

if [[ $# -gt 1 ]]; then
  echo "Usage:"
  echo "  ./scripts/generate_app_icon.sh"
  echo "  ./scripts/generate_app_icon.sh /path/to/custom-1024.png"
  exit 1
fi

if [[ -n "$CUSTOM_SOURCE" && ! -f "$CUSTOM_SOURCE" ]]; then
  echo "Error: custom PNG not found at '$CUSTOM_SOURCE'"
  exit 1
fi

if [[ -n "$CUSTOM_SOURCE" ]]; then
  CUSTOM_ABS_PATH="$(cd "$(dirname "$CUSTOM_SOURCE")" && pwd)/$(basename "$CUSTOM_SOURCE")"
  if [[ "$CUSTOM_ABS_PATH" != "$OUT_PNG" ]]; then
    cp "$CUSTOM_SOURCE" "$OUT_PNG"
  fi
else
  cat > "$TMP_SWIFT" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: swift generate_icon.swift <output_png_path>\n", stderr)
    exit(1)
}

let outputPath = args[1]
let canvasSize: CGFloat = 1024
let canvasRect = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)

let image = NSImage(size: canvasRect.size)
image.lockFocus()

if let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.09, green: 0.22, blue: 0.43, alpha: 1.0),
    ending: NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.24, alpha: 1.0)
) {
    gradient.draw(in: canvasRect, angle: -90)
}

let insetRect = canvasRect.insetBy(dx: 84, dy: 84)
let badgePath = NSBezierPath(roundedRect: insetRect, xRadius: 190, yRadius: 190)
NSColor.white.withAlphaComponent(0.14).setFill()
badgePath.fill()

let badgeStrokePath = NSBezierPath(roundedRect: insetRect, xRadius: 190, yRadius: 190)
badgeStrokePath.lineWidth = 8
NSColor.white.withAlphaComponent(0.28).setStroke()
badgeStrokePath.stroke()

let monogram = NSAttributedString(
    string: "W",
    attributes: [
        .font: NSFont.systemFont(ofSize: 560, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.95)
    ]
)

let monogramSize = monogram.size()
let monogramRect = NSRect(
    x: (canvasSize - monogramSize.width) / 2,
    y: (canvasSize - monogramSize.height) / 2 - 8,
    width: monogramSize.width,
    height: monogramSize.height
)

monogram.draw(in: monogramRect)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Failed to render icon image.\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    fputs("Failed to write icon PNG: \(error.localizedDescription)\n", stderr)
    exit(1)
}
SWIFT

  swift "$TMP_SWIFT" "$OUT_PNG"
fi

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$OUT_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$OUT_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$OUT_ICNS"

echo "Generated:"
echo "  PNG:  $OUT_PNG"
echo "  ICNS: $OUT_ICNS"
echo
if [[ -n "$CUSTOM_SOURCE" ]]; then
  echo "Used custom PNG source: $CUSTOM_SOURCE"
else
  echo "Generated default placeholder icon art."
fi
echo "To swap the icon later:"
echo "  ./scripts/generate_app_icon.sh /absolute/path/to/your-custom-1024.png"
