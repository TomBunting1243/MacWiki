import SwiftUI

struct DiscoverHoverEffect: ViewModifier {
    enum Profile {
        case hero
        case card
        case row
        case chip

        var scale: CGFloat {
            switch self {
            case .hero:
                return 1.004
            case .card:
                return 1.003
            case .row, .chip:
                return 1
            }
        }

        var duration: Double {
            switch self {
            case .chip:
                return 0.12
            case .row:
                return 0.13
            case .hero, .card:
                return 0.14
            }
        }

        var activeShadowOpacity: Double {
            switch self {
            case .hero:
                return 0.07
            case .card:
                return 0.045
            case .row, .chip:
                return 0
            }
        }

        var shadowRadius: CGFloat {
            switch self {
            case .hero:
                return 12
            case .card:
                return 8
            case .row, .chip:
                return 0
            }
        }

        var shadowY: CGFloat {
            switch self {
            case .hero:
                return 5
            case .card:
                return 4
            case .row, .chip:
                return 0
            }
        }

        var activeYOffset: CGFloat {
            switch self {
            case .hero:
                return -1.5
            case .card:
                return -1
            case .row, .chip:
                return 0
            }
        }
    }

    let profile: Profile
    let isActive: Bool
    let reduceMotion: Bool
    @Environment(\.macWikiAccessibilityPersonalization.reduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shadowIsActive = isActive && !reduceMotion && !reduceTransparency

        content
            .scaleEffect(reduceMotion ? 1 : (isActive ? profile.scale : 1))
            .offset(y: reduceMotion ? 0 : (isActive ? profile.activeYOffset : 0))
            .shadow(
                color: Color.black.opacity(shadowIsActive ? profile.activeShadowOpacity : 0),
                radius: shadowIsActive ? profile.shadowRadius : 0,
                y: shadowIsActive ? profile.shadowY : 0
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: profile.duration),
                value: isActive
            )
    }
}

extension View {
    func discoverHoverEffect(
        _ profile: DiscoverHoverEffect.Profile,
        isActive: Bool,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            DiscoverHoverEffect(
                profile: profile,
                isActive: isActive,
                reduceMotion: reduceMotion
            )
        )
    }
}
