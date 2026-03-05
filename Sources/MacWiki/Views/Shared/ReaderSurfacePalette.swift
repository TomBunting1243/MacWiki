import SwiftUI

enum ReaderSurfacePalette {
    // Keep in sync with `--reader-surface` in `Sources/MacWiki/Views/Components/WebView.swift`.
    private static let lightSurface = Color.white
    private static let darkSurface = Color(.sRGB, red: 30.0 / 255.0, green: 36.0 / 255.0, blue: 52.0 / 255.0, opacity: 1)

    static func surface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? darkSurface : lightSurface
    }
}

