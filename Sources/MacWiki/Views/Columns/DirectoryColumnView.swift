import SwiftUI

struct DirectoryColumnView: View {
    private enum Chrome {
        static let topInset: CGFloat = 8
        static let trafficLightColumnThreshold: CGFloat = 150
        static let verticalSpacingAnimation = ColumnMotion.sidebarVisibility
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppStorageKey.MainWindow.directoryWidth) private var directoryWidth = AppStorageKey.MainWindow.directoryWidthDefault
    @State private var measuredTopInset = Chrome.topInset
    @State private var hasMeasuredTrafficLightAvoidance = false

    @Binding var selectedList: ReadingList?
    @Binding var rootSelection: SidebarRootSelection

    let selectedLabel: Label?
    let selectedTag: Tag?
    let sidebarSearchModel: SidebarSearchSurfaceModel
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    private var resolvedTopInset: CGFloat {
        measuredTopInset
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SidebarPaneBackground()

            DirectoryView(
                selectedList: $selectedList,
                rootSelection: $rootSelection,
                selectedLabel: selectedLabel,
                selectedTag: selectedTag,
                sidebarSearchModel: sidebarSearchModel,
                onNewLabelWithArticle: onNewLabelWithArticle,
                onNewTagWithArticle: onNewTagWithArticle
            )
            .padding(.top, resolvedTopInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updateTrafficLightAvoidance(
                            minX: proxy.frame(in: .global).minX,
                            topSafeArea: proxy.safeAreaInsets.top
                        )
                    }
                    .onChange(of: proxy.frame(in: .global).minX) { _, minX in
                        updateTrafficLightAvoidance(
                            minX: minX,
                            topSafeArea: proxy.safeAreaInsets.top
                        )
                    }
                    .onChange(of: proxy.safeAreaInsets.top) { _, topSafeArea in
                        updateTrafficLightAvoidance(
                            minX: proxy.frame(in: .global).minX,
                            topSafeArea: topSafeArea
                        )
                    }
            }
        }
        .navigationSplitViewColumnWidth(
            min: MainWindowColumnWidth.directoryRange.lowerBound,
            ideal: CGFloat(directoryWidth),
            max: MainWindowColumnWidth.directoryRange.upperBound
        )
        .persistedColumnWidth(
            key: AppStorageKey.MainWindow.directoryWidth,
            range: MainWindowColumnWidth.directoryRange
        )
    }

    private func updateTrafficLightAvoidance(minX: CGFloat, topSafeArea: CGFloat) {
        let nextTopInset = minX < Chrome.trafficLightColumnThreshold
            ? Chrome.topInset + max(0, topSafeArea)
            : Chrome.topInset
        guard abs(measuredTopInset - nextTopInset) > 0.5 else {
            return
        }

        DispatchQueue.main.async {
            guard abs(measuredTopInset - nextTopInset) > 0.5 else { return }

            let update = {
                measuredTopInset = nextTopInset
                hasMeasuredTrafficLightAvoidance = true
            }

            if hasMeasuredTrafficLightAvoidance {
                withAnimation(reduceMotion ? nil : Chrome.verticalSpacingAnimation, update)
            } else {
                update()
            }
        }
    }
}
