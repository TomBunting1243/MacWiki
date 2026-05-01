import Foundation

enum AppStorageKey {
    enum Chrome {
        static let liquidGlassChrome = "tabBarLiquidGlass"
        static let tabBarLiquidGlass = liquidGlassChrome
        static let nativeHighlightingMenuEnabled = "nativeHighlightingMenuEnabled"
        static let nativeHighlightingMenuEnabledDefault = true
    }

    enum Reader {
        static let linkPreviewImmediateModifier = "reader.linkPreviewImmediateModifier"
    }

    enum Search {
        static let presentationMode = "searchPresentationMode"
    }

    enum MainWindow {
        static let sidebarWidth = "mainWindow.sidebarWidth"
        static let directoryWidth = "mainWindow.directoryWidth"
        static let inspectorWidth = "mainWindow.inspectorWidth"

        static let sidebarWidthDefault = 220.0
        static let directoryWidthDefault = 320.0
        static let inspectorWidthDefault = 320.0
    }

    enum ArticleWindow {
        static let inspectorWidth = "articleWindow.inspectorWidth"
        static let inspectorWidthDefault = 320.0
    }

    enum Features {
        static let wikiHopPostV1Enabled = "features.wikiHopPostV1Enabled"
    }

    enum Discover {
        static let openMode = "discoverOpenMode"
        static let sidebarTimeMachineHidden = "discover.sidebar.timeMachineHidden"
    }

    enum Recents {
        static let scope = "recentsScope"
    }

    enum Labels {
        static let displayMode = "labelDisplayMode"
    }

    enum Highlights {
        static let markerStyle = "highlightMarkerStyle"
        static let headerWrap = "highlightHeaderWrap"
    }

    enum ListsSidebar {
        static let sortOrder = "sidebarSortOrder"
    }

    enum Inspector {
        static let infoSplitRatio = "inspectorInfoSplitRatio"
        static let metadataSectionHeight = "inspectorMetadataSectionHeight"
        static let tocSectionHeight = "inspectorTOCSectionHeight"
    }

    enum OptionClickSave {
        static let defaultListID = "optionClickSave.defaultListID"
    }
}
