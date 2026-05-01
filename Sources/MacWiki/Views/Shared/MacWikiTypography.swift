import SwiftUI

enum MacWikiTypography {
    static let columnSectionLabel = Font.subheadline.weight(.semibold)
    static let columnHeaderTitle = Font.system(size: 20, weight: .semibold)
    static let columnHeaderMetadata = Font.callout.weight(.semibold)
    static let columnSearchField = Font.system(size: 17, weight: .regular)

    static let articleListTitle = Font.body.weight(.semibold)
    static let articleListSubtitle = Font.subheadline
    static let articleListExcerpt = Font.subheadline
    static let articleListMetadata = Font.footnote.weight(.medium)

    static let inspectorSectionLabel = Font.subheadline.weight(.semibold)
    static let inspectorTOCItem = Font.footnote
    static let inspectorTOCItemActive = Font.footnote.weight(.medium)
    static let metadataLabel = Font.caption.weight(.medium)
    static let metadataValue = Font.callout
    static let referenceBadge = Font.caption.weight(.medium)

    static let compactRowTitle = Font.subheadline.weight(.semibold)
    static let compactRowBody = Font.subheadline
    static let compactRowMetadata = Font.caption.weight(.medium)
    static let compactStatistic = Font.caption.weight(.medium)

    static let controlValue = Font.subheadline.weight(.medium)
    static let controlAuxiliary = Font.caption.weight(.medium)
    static let settingsHelp = Font.footnote
    static let emptyStateDescription = Font.footnote.weight(.medium)
}
