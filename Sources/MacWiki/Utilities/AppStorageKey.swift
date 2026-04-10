import Foundation

enum AppStorageKey {
    enum Chrome {
        static let tabBarLiquidGlass = "tabBarLiquidGlass"
        static let nativeHighlightingMenuEnabled = "nativeHighlightingMenuEnabled"
    }

    enum Search {
        static let presentationMode = "searchPresentationMode"
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
