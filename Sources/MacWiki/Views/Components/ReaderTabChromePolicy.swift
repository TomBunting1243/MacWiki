import SwiftUI

enum ReaderTabLaneMetrics {
    static let height: CGFloat = ColumnChromeMetrics.secondaryBarHeight
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 2
    static let tabMaxWidth: CGFloat = 240
    static let tabMinWidth: CGFloat = 120
    static let newTabButtonSize: CGFloat = 24
    static let tabSpacing: CGFloat = 4
    static let tabHeight: CGFloat = 28
    static let tabCornerRadius: CGFloat = 6
}
enum TabChromeHierarchy {
    static func titleActiveOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.98 : 0.96
    }

    static func titleHoverOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.92 : 0.90
    }

    static func titleInactiveOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.84 : 0.82
    }

    static func inactiveSurfaceOpacity(darkMode: Bool, isHovered: Bool) -> Double {
        if isHovered {
            return darkMode ? 0.075 : 0.055
        }
        return darkMode ? 0.035 : 0.018
    }

    static func borderOpacity(
        isActive: Bool,
        isHovered: Bool,
        isKeyWindow: Bool,
        darkMode: Bool,
        increasedContrast: Bool
    ) -> Double {
        if increasedContrast {
            return isKeyWindow ? 0.72 : 0.52
        }
        if isActive {
            return isKeyWindow ? (darkMode ? 0.34 : 0.28) : 0.20
        }
        if isHovered {
            return darkMode ? 0.88 : 0.96
        }
        return darkMode ? 0.62 : 0.78
    }

    static func progressTrackOpacity(darkMode: Bool, isActive: Bool) -> Double {
        if isActive {
            return darkMode ? 0.09 : 0.07
        }
        return darkMode ? 0.11 : 0.09
    }

    static func progressFillOpacity(darkMode: Bool, isActive: Bool) -> Double {
        if isActive {
            return darkMode ? 0.54 : 0.46
        }
        return darkMode ? 0.48 : 0.40
    }

    static func activeLiftYOffset() -> CGFloat {
        -0.12
    }

    static func activeShadowOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.05 : 0.025
    }

    static func activeShadowRadius() -> CGFloat {
        0.8
    }

    static func activeShadowYOffset() -> CGFloat {
        0.35
    }

}

struct TabInteractionProfile {
    let tabSelect: Animation?
    let tabCreateClose: Animation?
    let neighborShift: Animation?
    let snapBack: Animation?
    let dragLift: Animation?
    let hover: Animation?
    let closeButtonShow: Animation?
    let closeButtonHide: Animation?
    let overflowAffordance: Animation?
    let dragAutoScroll: Animation?
    let dragAutoScrollThrottle: TimeInterval
    let dragEdgeThreshold: CGFloat
    let dragStartDistance: CGFloat

    static func resolve(
        for viewportWidth: CGFloat,
        reduceMotion: Bool
    ) -> TabInteractionProfile {
        let width = viewportWidth > 0 ? viewportWidth : 900
        let density = TopChromeMotion.Density.resolve(for: width)

        if reduceMotion {
            switch density {
            case .compact:
                return TabInteractionProfile(
                    tabSelect: nil,
                    tabCreateClose: nil,
                    neighborShift: nil,
                    snapBack: nil,
                    dragLift: nil,
                    hover: nil,
                    closeButtonShow: nil,
                    closeButtonHide: nil,
                    overflowAffordance: nil,
                    dragAutoScroll: nil,
                    dragAutoScrollThrottle: 0.045,
                    dragEdgeThreshold: 34,
                    dragStartDistance: 4
                )
            case .regular:
                return TabInteractionProfile(
                    tabSelect: nil,
                    tabCreateClose: nil,
                    neighborShift: nil,
                    snapBack: nil,
                    dragLift: nil,
                    hover: nil,
                    closeButtonShow: nil,
                    closeButtonHide: nil,
                    overflowAffordance: nil,
                    dragAutoScroll: nil,
                    dragAutoScrollThrottle: 0.05,
                    dragEdgeThreshold: 42,
                    dragStartDistance: 4
                )
            case .spacious:
                return TabInteractionProfile(
                    tabSelect: nil,
                    tabCreateClose: nil,
                    neighborShift: nil,
                    snapBack: nil,
                    dragLift: nil,
                    hover: nil,
                    closeButtonShow: nil,
                    closeButtonHide: nil,
                    overflowAffordance: nil,
                    dragAutoScroll: nil,
                    dragAutoScrollThrottle: 0.06,
                    dragEdgeThreshold: 50,
                    dragStartDistance: 5
                )
            }
        }

        switch density {
        case .compact:
            return TabInteractionProfile(
                tabSelect: TopChromeMotion.tabSelect(density: density),
                tabCreateClose: TopChromeMotion.tabCreateClose(density: density),
                neighborShift: TopChromeMotion.neighborShift(density: density),
                snapBack: TopChromeMotion.snapBack(density: density),
                dragLift: TopChromeMotion.dragLift(density: density),
                hover: TopChromeMotion.hover(density: density),
                closeButtonShow: TopChromeMotion.closeReveal(density: density),
                closeButtonHide: TopChromeMotion.closeHide(density: density),
                overflowAffordance: TopChromeMotion.overflowAffordance(density: density),
                dragAutoScroll: TopChromeMotion.dragAutoScroll(density: density),
                dragAutoScrollThrottle: 0.045,
                dragEdgeThreshold: 34,
                dragStartDistance: 4
            )
        case .regular:
            return TabInteractionProfile(
                tabSelect: TopChromeMotion.tabSelect(density: density),
                tabCreateClose: TopChromeMotion.tabCreateClose(density: density),
                neighborShift: TopChromeMotion.neighborShift(density: density),
                snapBack: TopChromeMotion.snapBack(density: density),
                dragLift: TopChromeMotion.dragLift(density: density),
                hover: TopChromeMotion.hover(density: density),
                closeButtonShow: TopChromeMotion.closeReveal(density: density),
                closeButtonHide: TopChromeMotion.closeHide(density: density),
                overflowAffordance: TopChromeMotion.overflowAffordance(density: density),
                dragAutoScroll: TopChromeMotion.dragAutoScroll(density: density),
                dragAutoScrollThrottle: 0.05,
                dragEdgeThreshold: 42,
                dragStartDistance: 4
            )
        case .spacious:
            return TabInteractionProfile(
                tabSelect: TopChromeMotion.tabSelect(density: density),
                tabCreateClose: TopChromeMotion.tabCreateClose(density: density),
                neighborShift: TopChromeMotion.neighborShift(density: density),
                snapBack: TopChromeMotion.snapBack(density: density),
                dragLift: TopChromeMotion.dragLift(density: density),
                hover: TopChromeMotion.hover(density: density),
                closeButtonShow: TopChromeMotion.closeReveal(density: density),
                closeButtonHide: TopChromeMotion.closeHide(density: density),
                overflowAffordance: TopChromeMotion.overflowAffordance(density: density),
                dragAutoScroll: TopChromeMotion.dragAutoScroll(density: density),
                dragAutoScrollThrottle: 0.06,
                dragEdgeThreshold: 50,
                dragStartDistance: 5
            )
        }
    }
}

enum TabAccessibilityStatus {
    static func value(
        isActive: Bool,
        isSaved: Bool,
        hasHighlights: Bool,
        isRead: Bool,
        showsProgress: Bool,
        progress: Double
    ) -> String {
        var parts: [String] = [isActive ? "Active tab" : "Inactive tab"]
        if isSaved {
            parts.append("saved")
        }
        if hasHighlights {
            parts.append("has highlights")
        }
        if isRead {
            parts.append("read")
        } else if showsProgress {
            let percent = Int((min(max(progress, 0), 1) * 100).rounded())
            parts.append("\(percent)% read")
        }
        return parts.joined(separator: ", ")
    }
}
