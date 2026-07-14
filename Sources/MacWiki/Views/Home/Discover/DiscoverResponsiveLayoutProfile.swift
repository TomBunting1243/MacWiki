import CoreGraphics

/// Discrete layout decisions derived from the width available to Discovery.
///
/// Keeping the exact width out of view state means a live window resize only
/// invalidates Discovery when it crosses a boundary that can change layout.
struct DiscoverResponsiveLayoutProfile: Equatable, Sendable {
    enum WidthBand: Int, Equatable, Sendable {
        case under720
        case from720
        case from760
        case from820
        case from880
        case from940
        case from1120
        case from1200
        case from1240
        case from1320
        case from1540
    }

    static let initial = Self(widthBand: .from940)

    let widthBand: WidthBand

    init?(width: CGFloat) {
        guard width > 0 else { return nil }

        let widthBand: WidthBand
        switch width {
        case ..<720:
            widthBand = .under720
        case ..<760:
            widthBand = .from720
        case ..<820:
            widthBand = .from760
        case ..<880:
            widthBand = .from820
        case ..<940:
            widthBand = .from880
        case ..<1120:
            widthBand = .from940
        case ..<1200:
            widthBand = .from1120
        case ..<1240:
            widthBand = .from1200
        case ..<1320:
            widthBand = .from1240
        case ..<1540:
            widthBand = .from1320
        default:
            widthBand = .from1540
        }

        self.init(widthBand: widthBand)
    }

    private init(widthBand: WidthBand) {
        self.widthBand = widthBand
    }

    var pageMaxWidth: CGFloat {
        if isAtLeast(.from1540) { return 1320 }
        if isAtLeast(.from1240) { return 1160 }
        return 980
    }

    var horizontalPadding: CGFloat {
        if widthBand == .under720 { return 18 }
        if isAtLeast(.from1540) { return 42 }
        return 28
    }

    var pageSectionSpacing: CGFloat {
        isBelow(.from820) ? 16 : 20
    }

    var timeMachineStageSpacing: CGFloat {
        isBelow(.from820) ? 18 : 22
    }

    var prefersWideTimeMachineControls: Bool {
        isAtLeast(.from760)
    }

    var showsInlineTimeMachineQuickJumps: Bool {
        isAtLeast(.from880)
    }

    var isUltraCompact: Bool {
        widthBand == .under720
    }

    var isVeryCompact: Bool {
        isBelow(.from820)
    }

    var isCompact: Bool {
        isBelow(.from940)
    }

    var feedSectionSpacing: CGFloat {
        if isUltraCompact { return 16 }
        if isVeryCompact { return 20 }
        return isCompact ? 22 : 26
    }

    var heroImageHeight: CGFloat {
        if isUltraCompact { return 172 }
        if isVeryCompact { return 190 }
        if isCompact { return 214 }
        if isAtLeast(.from1320) { return 320 }
        if isAtLeast(.from1120) { return 286 }
        return 252
    }

    var leadStoryTitleLineLimit: Int {
        if isUltraCompact { return 3 }
        if isVeryCompact { return 4 }
        return 5
    }

    var leadStoryDescriptionLineLimit: Int {
        if isUltraCompact { return 2 }
        if isVeryCompact { return 3 }
        return 4
    }

    var inTheNewsRailLimit: Int {
        isCompact ? 8 : 12
    }

    var newsBriefingLimit: Int {
        if isUltraCompact { return 2 }
        if isVeryCompact { return 3 }
        if isCompact { return 4 }
        return 6
    }

    var allTimeMostReadLimit: Int {
        if isUltraCompact { return 10 }
        if isAtLeast(.from1200) { return 22 }
        return isVeryCompact ? 14 : 18
    }

    var playlistRowLimit: Int {
        if isUltraCompact { return 6 }
        if isAtLeast(.from1200) { return 12 }
        return isVeryCompact ? 8 : 10
    }

    var todayMostReadLimit: Int {
        if isUltraCompact { return 8 }
        if isVeryCompact { return 10 }
        if isAtLeast(.from1200) { return 14 }
        return 12
    }

    private func isAtLeast(_ other: WidthBand) -> Bool {
        widthBand.rawValue >= other.rawValue
    }

    private func isBelow(_ other: WidthBand) -> Bool {
        widthBand.rawValue < other.rawValue
    }
}
