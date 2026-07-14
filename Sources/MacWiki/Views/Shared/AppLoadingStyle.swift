import SwiftUI

enum AppLoadingTone {
    case neutral
    case accent

    func accentColor(for colorScheme: ColorScheme, override: Color? = nil) -> Color {
        if let override {
            return override
        }

        switch self {
        case .neutral:
            return Color.primary.opacity(colorScheme == .dark ? 0.82 : 0.78)
        case .accent:
            return Color.accentColor.opacity(colorScheme == .dark ? 0.92 : 0.88)
        }
    }

    func iconPlateFill(for colorScheme: ColorScheme, override: Color? = nil) -> Color {
        let accent = accentColor(for: colorScheme, override: override)
        switch self {
        case .neutral:
            return accent.opacity(colorScheme == .dark ? 0.14 : 0.11)
        case .accent:
            return accent.opacity(colorScheme == .dark ? 0.18 : 0.14)
        }
    }

    func barColors(for colorScheme: ColorScheme) -> [Color] {
        switch self {
        case .neutral:
            return [
                Color.primary.opacity(colorScheme == .dark ? 0.17 : 0.10),
                Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.05)
            ]
        case .accent:
            return [
                Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12),
                Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.05)
            ]
        }
    }

    func surfaceWash(for colorScheme: ColorScheme) -> LinearGradient {
        switch self {
        case .neutral:
            return LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.18),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .accent:
            return LinearGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.10),
                    Color.white.opacity(colorScheme == .dark ? 0.03 : 0.10),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    func strokeColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .neutral:
            return Color.white.opacity(colorScheme == .dark ? 0.10 : 0.22)
        case .accent:
            return Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.18)
        }
    }
}
