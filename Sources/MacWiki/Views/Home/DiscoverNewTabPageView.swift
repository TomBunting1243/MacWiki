import SwiftUI
import SwiftData
import Foundation

/// Apple News-inspired discovery hub used by the New Tab page.
struct DiscoverNewTabPageView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]

    @State private var searchCoordinator = SearchCoordinator(
        debounceMilliseconds: SearchCoordinator.defaultDebounceMilliseconds,
        minimumQueryLength: 2,
        supportsTrending: false,
        searchPrefetchLimit: 24
    )
    @State private var discoverFeedStore = DiscoverFeedStore()
    @State private var isAppeared = false
    @State private var selectedDiscoverDate = Date()
    @State private var discoverContentWidth: CGFloat = 1040
    @State private var discoverRefreshGeneration = 0
    @State private var activeSearchResultPageViewsPopover: DiscoverInlinePageViewsPopoverPayload?
    @State private var isTimeMachineDatePickerPresented = false
    @State private var timeMachineLensLastDragX: CGFloat?
    @State private var timeMachineLensDragAccumulatedX: CGFloat = 0
    @State private var discoverDateLoadTask: Task<Void, Never>?
    @State private var timeTravelSkeletonDelayTask: Task<Void, Never>?
    @State private var shouldShowDelayedTimeTravelSkeleton = false

    @FocusState private var isSearchFocused: Bool

    private var discoverReferenceDate: Date {
        Calendar.current.startOfDay(for: selectedDiscoverDate)
    }

    private var selectedDiscoverDateKey: String {
        Self.discoverFeedDateFormatter.string(from: discoverReferenceDate)
    }

    private var shouldQueueTimeTravelSkeleton: Bool {
        guard discoverFeedStore.isLoading else { return false }
        guard let visibleFeed = discoverFeedStore.feed else { return false }
        return visibleFeed.dateKey != selectedDiscoverDateKey
    }

    private var showsTimeTravelSkeleton: Bool {
        shouldShowDelayedTimeTravelSkeleton && shouldQueueTimeTravelSkeleton
    }

    private var savedArticleTitlesNormalized: Set<String> {
        SearchResultActions.savedArticleTitlesNormalized(from: allLists)
    }

    @AppStorage(DiscoverStartMode.storageKey) private var discoverStartMode: DiscoverStartMode = .discoverFeed
    @AppStorage(ExperimentFlag.wikiHopPOCEnabled.key) private var isWikiHopEnabled = false
    @AppStorage("features.wikiHopPostV1Enabled") private var isWikiHopPostV1Enabled = false

    private var isWikiHopAvailable: Bool {
        isWikiHopPostV1Enabled && isWikiHopEnabled
    }

    var body: some View {
        if isWikiHopAvailable && discoverStartMode == .wikiHop {
            WikiHopLobbyView()
        } else {
            discoverFeedContent
        }
    }

    private var discoverFeedContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: discoverContentWidth < 820 ? 18 : 22) {
                searchBar

                if searchCoordinator.hasQuery {
                    searchResultsSurface
                } else {
                    discoverControls
                    discoverSurface
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 48)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            updateDiscoverContentWidth(proxy.size.width)
                        }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            updateDiscoverContentWidth(newWidth)
                        }
                }
            }
        }
        .background(discoverBackground.ignoresSafeArea())
        .onAppear {
            if reduceMotion {
                isAppeared = true
            } else {
                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88)) {
                    isAppeared = true
                }
            }
            isSearchFocused = true
            updateTimeTravelSkeletonVisibility()
        }
        .onDisappear {
            if !reduceMotion {
                isAppeared = false
            }
            searchCoordinator.cancel()
            discoverDateLoadTask?.cancel()
            timeTravelSkeletonDelayTask?.cancel()
            timeTravelSkeletonDelayTask = nil
            shouldShowDelayedTimeTravelSkeleton = false
            discoverFeedStore.cancel()
        }
        .onChange(of: shouldQueueTimeTravelSkeleton) { _, _ in
            updateTimeTravelSkeletonVisibility()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                isAppeared = true
            }
        }
        .onChange(of: selectedDiscoverDate) { _, _ in
            guard !searchCoordinator.hasQuery else { return }
            activeSearchResultPageViewsPopover = nil
            queueDiscoverLoadDebounced()
        }
        .task {
            queueDiscoverLoadDebounced(delayNanoseconds: 0)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search Wikipedia", text: $searchCoordinator.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .focused($isSearchFocused)
                .onSubmit {
                    if let first = searchCoordinator.searchResults.first {
                        open(first, inNewTab: false)
                    }
                }

            if searchCoordinator.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if !searchCoordinator.hasQuery {
                Button {
                    queueDiscoverLoadDebounced(forceRefresh: true, delayNanoseconds: 0)
                    discoverRefreshGeneration += 1
                } label: {
                    Group {
                        if discoverFeedStore.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(DiscoverInteractivePressStyle())
                .disabled(discoverFeedStore.isLoading)
                .help(discoverFeedStore.isLoading ? "Refreshing Discover…" : "Refresh Discover")
            } else if searchCoordinator.hasInput {
                Button {
                    searchCoordinator.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(DiscoverInteractivePressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
    }

    private var discoverControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary.opacity(0.82))
                    .frame(width: 20, height: 20)

                Text("Time Machine")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.92))

                Spacer(minLength: 0)

                Text(discoverFeedStore.feed?.dateLabel ?? discoverTimeMachineDateLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if prefersWideTimeMachineControls {
                HStack(spacing: 6) {
                    discoverTimeMachineStepButton("chevron.left") {
                        shiftDiscoverDate(days: -1)
                    }

                    discoverTimeMachineTemporalLensButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    discoverTimeMachineStepButton("chevron.right", disabled: !canStepDiscoverDateForward) {
                        shiftDiscoverDate(days: 1)
                    }

                    discoverTimeMachineJumpMenuButton
                    discoverTimeMachineRefreshButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 1)

                if showsInlineTimeMachineQuickJumps {
                    discoverTimeMachineQuickJumpRow
                        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .leading)))
                }
            } else {
                HStack(spacing: 6) {
                    discoverTimeMachineStepButton("chevron.left") {
                        shiftDiscoverDate(days: -1)
                    }

                    discoverTimeMachineTemporalLensButton
                        .layoutPriority(1)

                    discoverTimeMachineStepButton("chevron.right", disabled: !canStepDiscoverDateForward) {
                        shiftDiscoverDate(days: 1)
                    }
                }

                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    discoverTimeMachineJumpMenuButton
                    discoverTimeMachineRefreshButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(nsColor: .systemBlue).opacity(colorScheme == .dark ? 0.12 : 0.07),
                            Color(nsColor: .systemCyan).opacity(colorScheme == .dark ? 0.08 : 0.04),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07), radius: 8, y: 3)
        .help("Temporal Lens: scrub day-by-day or jump to a specific date.")
    }

    private var prefersWideTimeMachineControls: Bool {
        discoverContentWidth >= 760
    }

    private var showsInlineTimeMachineQuickJumps: Bool {
        discoverContentWidth >= 880
    }

    @ViewBuilder
    private var discoverTimeMachineQuickJumpRow: some View {
        HStack(spacing: 6) {
            discoverTimeMachineQuickJumpButton("Today", disabled: isDiscoverDateToday) {
                selectedDiscoverDate = Date()
            }
            discoverTimeMachineQuickJumpButton("Yesterday") {
                shiftDiscoverDate(days: -1)
            }
            discoverTimeMachineQuickJumpButton("7D") {
                shiftDiscoverDate(days: -7)
            }
            discoverTimeMachineQuickJumpButton("30D") {
                shiftDiscoverDate(days: -30)
            }
            discoverTimeMachineQuickJumpButton("1Y") {
                shiftDiscoverDate(years: -1)
            }
            discoverTimeMachineQuickJumpButton("5Y") {
                shiftDiscoverDate(years: -5)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 1)
    }

    private var canStepDiscoverDateForward: Bool {
        discoverReferenceDate < Calendar.current.startOfDay(for: Date())
    }

    private var isDiscoverDateToday: Bool {
        Calendar.current.isDate(discoverReferenceDate, inSameDayAs: Date())
    }

    private var discoverTimeMachineDateLabel: String {
        Self.timeMachineCompactDateFormatter.string(from: discoverReferenceDate)
    }

    private func shiftDiscoverDate(days: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let shifted = calendar.date(byAdding: .day, value: days, to: discoverReferenceDate) ?? discoverReferenceDate
        selectedDiscoverDate = min(shifted, today)
    }

    private func shiftDiscoverDate(years: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let shifted = calendar.date(byAdding: .year, value: years, to: discoverReferenceDate) ?? discoverReferenceDate
        selectedDiscoverDate = min(shifted, today)
    }

    private func queueDiscoverLoadDebounced(
        forceRefresh: Bool = false,
        delayNanoseconds: UInt64 = 170_000_000
    ) {
        discoverDateLoadTask?.cancel()
        discoverDateLoadTask = Task { @MainActor in
            if !forceRefresh, delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled else { return }
            }
            discoverFeedStore.queueLoad(referenceDate: discoverReferenceDate, forceRefresh: forceRefresh)
        }
    }

    private static let timeTravelSkeletonDelayNanoseconds: UInt64 = 1_600_000_000

    private func updateTimeTravelSkeletonVisibility() {
        timeTravelSkeletonDelayTask?.cancel()
        timeTravelSkeletonDelayTask = nil

        guard shouldQueueTimeTravelSkeleton else {
            if shouldShowDelayedTimeTravelSkeleton {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                    shouldShowDelayedTimeTravelSkeleton = false
                }
            } else {
                shouldShowDelayedTimeTravelSkeleton = false
            }
            return
        }

        guard !shouldShowDelayedTimeTravelSkeleton else { return }
        timeTravelSkeletonDelayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.timeTravelSkeletonDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard shouldQueueTimeTravelSkeleton else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                shouldShowDelayedTimeTravelSkeleton = true
            }
        }
    }

    private func stepTimeMachineLensByDrag(deltaX: CGFloat) {
        timeMachineLensDragAccumulatedX += deltaX
        let threshold: CGFloat = 18

        while abs(timeMachineLensDragAccumulatedX) >= threshold {
            let isForward = timeMachineLensDragAccumulatedX > 0
            shiftDiscoverDate(days: isForward ? 1 : -1)
            timeMachineLensDragAccumulatedX += isForward ? -threshold : threshold
        }
    }

    private func resetTimeMachineLensDrag() {
        timeMachineLensLastDragX = nil
        timeMachineLensDragAccumulatedX = 0
    }

    @ViewBuilder
    private func discoverTimeMachineStepButton(
        _ symbol: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .foregroundStyle(.primary.opacity(disabled ? 0.36 : 0.86))
        .background(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private func discoverTimeMachineQuickJumpButton(
        _ title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 9)
                .frame(height: 22)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .foregroundStyle(.primary.opacity(disabled ? 0.36 : 0.86))
        .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.09), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var discoverTimeMachineTemporalLensButton: some View {
        Button {
            isTimeMachineDatePickerPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 10.5, weight: .semibold))

                Text(discoverTimeMachineDateLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary.opacity(0.88))
        .background(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.6)
        )
        .popover(isPresented: $isTimeMachineDatePickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker(
                    "Jump to date",
                    selection: $selectedDiscoverDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()

                HStack(spacing: 8) {
                    Button("Today") {
                        selectedDiscoverDate = Date()
                    }
                    .disabled(isDiscoverDateToday)

                    Spacer(minLength: 0)

                    Button("Done") {
                        isTimeMachineDatePickerPresented = false
                    }
                }
                .font(.system(size: 11.5, weight: .semibold))
            }
            .padding(10)
            .frame(width: 250)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if let lastX = timeMachineLensLastDragX {
                        stepTimeMachineLensByDrag(deltaX: value.location.x - lastX)
                    }
                    timeMachineLensLastDragX = value.location.x
                }
                .onEnded { _ in
                    resetTimeMachineLensDrag()
                }
        )
        .help("Drag left/right to scrub days")
    }

    @ViewBuilder
    private var discoverTimeMachineRefreshButton: some View {
        Button {
            queueDiscoverLoadDebounced(forceRefresh: true, delayNanoseconds: 0)
            discoverRefreshGeneration += 1
        } label: {
            Image(systemName: discoverFeedStore.isLoading ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary.opacity(discoverFeedStore.isLoading ? 0.38 : 0.86))
        .background(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.6)
        )
        .disabled(discoverFeedStore.isLoading)
        .help("Refresh Discover")
    }

    @ViewBuilder
    private var discoverTimeMachineJumpMenuButton: some View {
        Menu {
            Button("Today", systemImage: "sun.max") {
                selectedDiscoverDate = Date()
            }
            .disabled(isDiscoverDateToday)

            Button("Yesterday", systemImage: "clock.arrow.circlepath") {
                shiftDiscoverDate(days: -1)
            }
            Button("7 days ago", systemImage: "calendar.badge.clock") {
                shiftDiscoverDate(days: -7)
            }
            Button("30 days ago", systemImage: "calendar") {
                shiftDiscoverDate(days: -30)
            }
            Button("1 year ago", systemImage: "clock.arrow.circlepath") {
                shiftDiscoverDate(years: -1)
            }
            Button("5 years ago", systemImage: "clock.arrow.2.circlepath") {
                shiftDiscoverDate(years: -5)
            }
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary.opacity(0.86))
        .background(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var searchResultsSurface: some View {
        let savedTitles = savedArticleTitlesNormalized
        VStack(alignment: .leading, spacing: 10) {
            DiscoverSectionHeader(title: "Search Results", subtitle: "\(searchCoordinator.searchResults.count) matches")
            if searchCoordinator.searchResults.isEmpty && !searchCoordinator.isLoading {
                Text("No matching articles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(searchCoordinator.searchResults.prefix(20)) { result in
                        let rowKey = "search:\(result.id):\(ReadStateSync.normalizedTitle(result.title))"
                        let isSaved = savedTitles.contains(ReadStateSync.normalizedTitle(result.title))
                        DiscoverSearchResultRow(result: result, isSaved: isSaved) {
                            let inNewTab = SystemBridge.isCommandPressed
                            open(result, inNewTab: inNewTab)
                        }
                        .contextMenu {
                            SearchResultContextMenuContent(
                                result: result,
                                allLists: allLists,
                                onOpen: { inNewTab in
                                    open(result, inNewTab: inNewTab)
                                },
                                onSaveToList: { list in
                                    SearchResultActions.saveToList(
                                        result,
                                        list: list,
                                        modelContext: modelContext
                                    )
                                },
                                onShowPageViews: {
                                    activeSearchResultPageViewsPopover = DiscoverInlinePageViewsPopoverPayload(
                                        rowKey: rowKey,
                                        title: result.title
                                    )
                                }
                            )
                        }
                        .popover(
                            isPresented: Binding(
                                get: { activeSearchResultPageViewsPopover?.rowKey == rowKey },
                                set: { isPresented in
                                    guard !isPresented else { return }
                                    if activeSearchResultPageViewsPopover?.rowKey == rowKey {
                                        activeSearchResultPageViewsPopover = nil
                                    }
                                }
                            ),
                            arrowEdge: .trailing
                        ) {
                            if let payload = activeSearchResultPageViewsPopover, payload.rowKey == rowKey {
                                DiscoverPageViewsPopoverContent(
                                    title: payload.title,
                                    referenceDate: discoverReferenceDate
                                )
                            }
                        }
                        if result.id != searchCoordinator.searchResults.prefix(20).last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var discoverSurface: some View {
        if discoverFeedStore.isLoading && discoverFeedStore.feed == nil {
            ProgressView("Loading today’s discover feed…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 220)
        } else if let discoverError = discoverFeedStore.errorMessage, discoverFeedStore.feed == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Discover feed unavailable")
                    .font(.headline)
                Text(discoverError)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if let feed = discoverFeedStore.feed {
            ZStack(alignment: .topLeading) {
                DiscoverFeedSections(
                    feed: feed,
                    availableWidth: discoverContentWidth,
                    isSearchFieldFocused: isSearchFocused,
                    refreshGeneration: discoverRefreshGeneration,
                    onOpen: { result, inNewTab in
                        open(result, inNewTab: inNewTab)
                    }
                )
                .opacity(isAppeared ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (isAppeared ? 0 : 10))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isAppeared)
                .opacity(showsTimeTravelSkeleton ? 0.34 : 1)
                .blur(radius: showsTimeTravelSkeleton && !reduceMotion ? 1.4 : 0)
                .allowsHitTesting(!showsTimeTravelSkeleton)

                if showsTimeTravelSkeleton {
                    DiscoverTimeTravelSkeletonView(
                        targetDate: discoverReferenceDate,
                        availableWidth: discoverContentWidth
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showsTimeTravelSkeleton)
        }
    }

    private var discoverBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.74)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accentColor.opacity(0.12), Color.accentColor.opacity(0)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 260
                    )
                )
                .offset(x: 250, y: -260)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.08), Color.blue.opacity(0)],
                        center: .center,
                        startRadius: 10,
                        endRadius: 220
                    )
                )
                .offset(x: -320, y: 180)

            RoundedRectangle(cornerRadius: 320, style: .continuous)
                .stroke(Color.primary.opacity(0.03), lineWidth: 1)
                .scaleEffect(1.2)
                .offset(y: 180)
        }
    }

    private func open(_ result: WikipediaService.SearchResult, inNewTab: Bool) {
        let article = Article(
            id: result.id,
            title: result.title,
            description: result.description,
            thumbnailURL: result.thumbnailURL
        )
        if SystemBridge.isOptionPressed {
            appState.presentOptionClickSavePrompt(for: article)
        } else {
            appState.openArticle(article, inNewTab: inNewTab)
        }
    }

    private func copyToClipboard(_ value: String) {
        _ = SystemBridge.copyText(value)
    }

    private func updateDiscoverContentWidth(_ newWidth: CGFloat) {
        guard newWidth > 0 else { return }
        guard abs(discoverContentWidth - newWidth) > 0.5 else { return }
        discoverContentWidth = newWidth
    }

    private static let discoverFeedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static let timeMachineCompactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

}

private struct DiscoverInlinePageViewsPopoverPayload {
    let rowKey: String
    let title: String
}

private struct DiscoverTimeTravelSkeletonView: View {
    let targetDate: Date
    let availableWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerPhase: CGFloat = -1.1
    @State private var isShimmerAnimating = false

    private var cardColumns: [GridItem] {
        if availableWidth < 840 {
            return [GridItem(.flexible(minimum: 240), spacing: 10)]
        }
        return [
            GridItem(.flexible(minimum: 220), spacing: 10),
            GridItem(.flexible(minimum: 220), spacing: 10)
        ]
    }

    private var targetDateLabel: String {
        Self.targetDateFormatter.string(from: targetDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.9))
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text("Time traveling to \(targetDateLabel)")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("Loading archive")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), in: Capsule(style: .continuous))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.17 : 0.10), lineWidth: 0.7)
            )

            HStack(alignment: .center, spacing: 7) {
                ForEach(0..<8, id: \.self) { index in
                    DiscoverTimeTravelPulsePip(
                        index: index,
                        shimmerPhase: shimmerPhase,
                        shimmerEnabled: !reduceMotion
                    )
                }
            }
            .frame(height: 18)

            LazyVGrid(columns: cardColumns, spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    DiscoverTimeTravelSkeletonCard(
                        index: index,
                        shimmerPhase: shimmerPhase,
                        shimmerEnabled: !reduceMotion
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.8)
        )
        .overlay {
            DiscoverGlitchScanlineOverlay(lineOpacity: colorScheme == .dark ? 0.12 : 0.08)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .blendMode(.screen)
                .opacity(reduceMotion ? 0.35 : 0.72)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.09), radius: 12, y: 5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            updateShimmerAnimation()
        }
        .onChange(of: reduceMotion) { _, _ in
            updateShimmerAnimation()
        }
        .onDisappear {
            isShimmerAnimating = false
        }
    }

    private func updateShimmerAnimation() {
        if reduceMotion {
            isShimmerAnimating = false
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                shimmerPhase = -1.1
            }
            return
        }

        guard !isShimmerAnimating else { return }
        isShimmerAnimating = true
        shimmerPhase = -1.1
        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
            shimmerPhase = 1.1
        }
    }

    private static let targetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter
    }()
}

private struct DiscoverTimeTravelPulsePip: View {
    let index: Int
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var pipHeight: CGFloat {
        6 + CGFloat((index % 3) * 3)
    }

    var body: some View {
        DiscoverTimeTravelSkeletonBar(
            width: nil,
            height: pipHeight,
            cornerRadius: 4.5,
            shimmerPhase: shimmerPhase,
            shimmerEnabled: shimmerEnabled,
            tiltDegrees: index.isMultiple(of: 2) ? -13 : 13
        )
        .frame(maxWidth: .infinity)
        .opacity(colorScheme == .dark ? 0.95 : 1)
    }
}

private struct DiscoverTimeTravelSkeletonCard: View {
    let index: Int
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var titleWidth: CGFloat {
        120 + CGFloat((index % 3) * 28)
    }

    private var subtitleWidth: CGFloat {
        84 + CGFloat((index % 2) * 24)
    }

    private var lineWidth: CGFloat {
        160 - CGFloat((index % 3) * 16)
    }

    private var glitchOffset: CGFloat {
        guard shimmerEnabled else { return 0 }
        let wave = sin((Double(shimmerPhase) * .pi * 5.2) + Double(index) * 0.9)
        let gate = max(0, sin((Double(shimmerPhase) * .pi * 13.0) + Double(index) * 0.55))
        return CGFloat(wave * gate) * 1.35
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DiscoverTimeTravelSkeletonBar(
                    width: 22,
                    height: 22,
                    cornerRadius: 7,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled,
                    tiltDegrees: -14
                )

                VStack(alignment: .leading, spacing: 5) {
                    DiscoverTimeTravelSkeletonBar(
                        width: titleWidth,
                        height: 10,
                        cornerRadius: 5,
                        shimmerPhase: shimmerPhase,
                        shimmerEnabled: shimmerEnabled
                    )
                    DiscoverTimeTravelSkeletonBar(
                        width: subtitleWidth,
                        height: 9,
                        cornerRadius: 5,
                        shimmerPhase: shimmerPhase,
                        shimmerEnabled: shimmerEnabled
                    )
                }

                Spacer(minLength: 0)
            }

            DiscoverTimeTravelSkeletonBar(
                width: nil,
                height: 12,
                cornerRadius: 6,
                shimmerPhase: shimmerPhase,
                shimmerEnabled: shimmerEnabled
            )
            DiscoverTimeTravelSkeletonBar(
                width: lineWidth,
                height: 10,
                cornerRadius: 5,
                shimmerPhase: shimmerPhase,
                shimmerEnabled: shimmerEnabled
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 0.7)
        )
        .overlay {
            if shimmerEnabled {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.red.opacity(colorScheme == .dark ? 0.16 : 0.11), lineWidth: 0.55)
                    .offset(x: glitchOffset * 0.75)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.cyan.opacity(colorScheme == .dark ? 0.16 : 0.11), lineWidth: 0.55)
                    .offset(x: -glitchOffset * 0.75)
            }
        }
        .offset(x: glitchOffset)
    }
}

private struct DiscoverTimeTravelSkeletonBar: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool
    var tiltDegrees: Double = 14

    @Environment(\.colorScheme) private var colorScheme

    private var baseGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.primary.opacity(colorScheme == .dark ? 0.17 : 0.10),
                Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glitchOffset: CGFloat {
        guard shimmerEnabled else { return 0 }
        let wave = sin((Double(shimmerPhase) * .pi * 4.6) + (tiltDegrees / 9))
        let gate = max(0, sin((Double(shimmerPhase) * .pi * 14.0) + (tiltDegrees / 5)))
        return CGFloat(wave * gate) * 1.2
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseGradient)
            .overlay {
                if shimmerEnabled {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        Color.white.opacity(colorScheme == .dark ? 0.28 : 0.50),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .rotationEffect(.degrees(tiltDegrees))
                            .offset(x: shimmerPhase * max(proxy.size.width, 1))
                    }
                    .clipped()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.07 : 0.12), lineWidth: 0.7)
            )
            .overlay {
                if shimmerEnabled {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.red.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 0.55)
                        .offset(x: glitchOffset)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.cyan.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 0.55)
                        .offset(x: -glitchOffset)
                    DiscoverGlitchScanlineOverlay(lineOpacity: colorScheme == .dark ? 0.14 : 0.10)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .blendMode(.screen)
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

private struct DiscoverGlitchScanlineOverlay: View {
    let lineOpacity: Double

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                var y: CGFloat = 0
                while y < proxy.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    y += 3
                }
            }
            .stroke(Color.white.opacity(lineOpacity), lineWidth: 0.45)
        }
        .allowsHitTesting(false)
    }
}

private enum DiscoverCollectionsMode: String, CaseIterable, Identifiable {
    case all
    case mostRead
    case longest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .mostRead: "Most Read"
        case .longest: "Longest"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .mostRead: "chart.line.uptrend.xyaxis"
        case .longest: "text.alignleft"
        }
    }
}

private enum DiscoverCollectionLane: String, CaseIterable {
    case mostRead
    case longest
}

private struct DiscoverFeedSections: View {
    let feed: WikipediaService.DiscoverFeed
    let availableWidth: CGFloat
    let isSearchFieldFocused: Bool
    let refreshGeneration: Int
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var allTimeMostReadStore = DiscoverAllTimeMostReadStore()
    @State private var todayMostReadStore = DiscoverTodayMostReadStore()
    @State private var trendPulseStore = DiscoverTrendPulseStore()
    @State private var todayTrendPulseStore = DiscoverTrendPulseStore()
    @State private var wordCountStore = DiscoverWordCountStore()
    @State private var featuredSummaryStore = DiscoverFeaturedSummaryStore()
    @State private var visualContextStore = DiscoverVisualContextStore()
    @State private var activePageViewsPopover: DiscoverPageViewsPopoverPayload?
    @State private var collectionsMode: DiscoverCollectionsMode = .all
    @State private var isCollectionsKeyboardFocusActive = false
    @State private var focusedCollectionLane: DiscoverCollectionLane = .mostRead
    @State private var focusedMostReadRowIndex = 0
    @State private var focusedLongestRowIndex = 0

    private var isUltraCompactLayout: Bool {
        availableWidth < 720
    }

    private var isVeryCompactLayout: Bool {
        availableWidth < 820
    }

    private var isCompactLayout: Bool {
        availableWidth < 940
    }

    private var sectionSpacing: CGFloat {
        if isUltraCompactLayout { return 16 }
        return isVeryCompactLayout ? 20 : (isCompactLayout ? 22 : 26)
    }

    private var heroImageHeight: CGFloat {
        if isUltraCompactLayout { return 162 }
        if isVeryCompactLayout { return 178 }
        if isCompactLayout { return 198 }
        return 224
    }

    private var isCollectionsStacked: Bool {
        availableWidth < 900 || collectionsMode != .all
    }

    private var showsMostReadCollection: Bool {
        collectionsMode != .longest
    }

    private var showsLongestCollection: Bool {
        collectionsMode != .mostRead
    }

    private var usesSegmentedCollectionsControl: Bool {
        availableWidth >= 780
    }

    private var collectionsControlWidth: CGFloat {
        min(max(availableWidth * 0.32, 220), 320)
    }

    private var playlistColumns: [GridItem] {
        if isCollectionsStacked {
            return [GridItem(.flexible(minimum: 280), spacing: 0)]
        }
        return [
            GridItem(.flexible(minimum: 300), spacing: 12),
            GridItem(.flexible(minimum: 300), spacing: 12)
        ]
    }

    private var newsBriefingLimit: Int {
        if isUltraCompactLayout { return 2 }
        if isVeryCompactLayout { return 3 }
        if isCompactLayout { return 4 }
        return 6
    }

    private var allTimeMostReadLimit: Int {
        if isUltraCompactLayout { return 10 }
        return isVeryCompactLayout ? 14 : 18
    }

    private var playlistRowLimit: Int {
        if collectionsMode == .all {
            if isUltraCompactLayout { return 6 }
            return isVeryCompactLayout ? 8 : 10
        }
        if isUltraCompactLayout { return 8 }
        return isVeryCompactLayout ? 10 : 14
    }

    private var allTimeMostReadLoadLimit: Int {
        max(allTimeMostReadLimit * 3, 48)
    }

    private var todayMostReadLimit: Int {
        if isUltraCompactLayout { return 8 }
        if isVeryCompactLayout { return 10 }
        return 12
    }

    private var allTimeMostReadEntries: [WikipediaService.AllTimeMostReadEntry] {
        Array(allTimeMostReadStore.entries.prefix(allTimeMostReadLimit))
    }

    private var todayMostReadItems: [WikipediaService.SearchResult] {
        Array(todayMostReadStore.results.prefix(todayMostReadLimit))
    }

    private var allTimeMostReadByTitleKey: [String: WikipediaService.AllTimeMostReadEntry] {
        allTimeMostReadStore.entries.reduce(into: [:]) { result, entry in
            let key = ReadStateSync.normalizedTitle(entry.result.title)
            guard !key.isEmpty else { return }
            result[key] = entry
        }
    }

    private var rankedMostReadItems: [WikipediaService.SearchResult] {
        allTimeMostReadEntries.map(\.result)
    }

    private var playlistMostReadItems: [WikipediaService.SearchResult] {
        Array(rankedMostReadItems.prefix(playlistRowLimit))
    }

    private var allTimeMostReadLoadKey: String {
        "\(allTimeMostReadLoadLimit)"
    }

    private var todayMostReadLoadKey: String {
        "today-most-read:\(refreshGeneration)"
    }

    private var todayTrendPulseLoadKey: String {
        "\(feed.dateKey)|\(todayMostReadItems.map(\.title).joined(separator: "|"))"
    }

    private var trendPulseLoadKey: String {
        "\(feed.dateKey)|\(playlistMostReadItems.map(\.title).joined(separator: "|"))"
    }

    private var featuredArticleTitle: String? {
        feed.featuredArticle?.title
    }

    private var featuredTeaserText: String? {
        guard let featuredArticleTitle else { return nil }
        return featuredSummaryStore.teaser(for: featuredArticleTitle)
    }

    private var isFeaturedTeaserLoading: Bool {
        featuredSummaryStore.isLoading && (featuredTeaserText == nil)
    }

    private var trendReferenceDate: Date {
        Self.featuredFeedDateFormatter.date(from: feed.dateKey) ?? Date()
    }

    private var mostReadPulseReferenceDate: Date {
        trendReferenceDate
    }

    private var todayMostReadSubtitle: String {
        if !todayMostReadItems.isEmpty {
            return "Today’s live ranking across Wikipedia"
        }
        if todayMostReadStore.isLoading {
            return "Loading today’s chart…"
        }
        if todayMostReadStore.errorMessage != nil {
            return "Today’s ranking is unavailable right now"
        }
        return "Today’s ranking is waiting for data"
    }

    private var playlistMostReadSubtitle: String {
        if !allTimeMostReadEntries.isEmpty {
            return "All-time leaders from Wikipedia’s monthly charts"
        }
        if allTimeMostReadStore.isLoading {
            return "Building all-time ranking…"
        }
        if allTimeMostReadStore.errorMessage != nil {
            return "All-time ranking unavailable right now"
        }
        return "All-time ranking is waiting for data"
    }

    private var playlistLongestSubtitle: String {
        "Longest deep dives from all-time popular reads"
    }

    private var mostReadCollectionMeta: String {
        let trackCount = playlistMostReadItems.count
        guard trackCount > 0 else {
            if allTimeMostReadStore.isLoading {
                return "Loading all-time tracks…"
            }
            return allTimeMostReadStore.errorMessage == nil
                ? "All-time tracks unavailable"
                : "All-time data unavailable"
        }

        let totalAllTimeViews = playlistMostReadItems.reduce(0) { partialResult, result in
            partialResult + (allTimeMostReadEntry(for: result)?.totalViews ?? 0)
        }
        let pulses = playlistMostReadItems.compactMap { mostReadPulse(for: $0) }
        var summary = "\(trackCount) tracks"
        if totalAllTimeViews > 0 {
            summary += " • \(abbreviatedViewCount(totalAllTimeViews)) all-time views"
        } else {
            summary += " • all-time views pending"
        }

        guard !pulses.isEmpty else {
            return trendPulseStore.isLoading ? "\(summary) • loading recent pulse" : summary
        }

        let risingCount = pulses.filter { (trendDeltaFraction(for: $0) ?? 0) > 0 }.count
        if risingCount > 0 {
            return "\(summary) • \(risingCount) rising now"
        }
        return summary
    }

    private var longestCollectionMeta: String {
        let trackCount = max(min(longestReadCandidates.count, playlistRowLimit), longestReadItems.count)
        guard !longestReadItems.isEmpty else {
            return wordCountStore.isLoading
                ? "\(trackCount) tracks • loading words"
                : "\(trackCount) tracks • metadata partial"
        }

        let averageWords = longestReadItems.reduce(0) { $0 + $1.wordCount } / max(longestReadItems.count, 1)
        let totalMinutes = longestReadItems.reduce(0) { partialResult, entry in
            partialResult + estimatedReadingMinutes(for: entry.wordCount)
        }
        return "\(longestReadItems.count) tracks • avg \(abbreviatedViewCount(averageWords)) words • \(formattedReadingDuration(minutes: totalMinutes)) total"
    }

    private var todayMostReadMeta: String {
        let trackCount = todayMostReadItems.count
        guard trackCount > 0 else {
            return todayMostReadStore.isLoading ? "Loading today’s tracks…" : "Today’s tracks unavailable"
        }

        let pulses = todayMostReadItems.compactMap { todayMostReadPulse(for: $0) }
        guard !pulses.isEmpty else {
            return todayTrendPulseStore.isLoading
                ? "\(trackCount) tracks • loading views"
                : "\(trackCount) tracks • views pending"
        }

        let totalViews = pulses.reduce(0) { $0 + $1.latestViews }
        let risingCount = pulses.filter { (trendDeltaFraction(for: $0) ?? 0) > 0 }.count
        if risingCount > 0 {
            return "\(trackCount) tracks • \(abbreviatedViewCount(totalViews)) today • \(risingCount) rising"
        }
        return "\(trackCount) tracks • \(abbreviatedViewCount(totalViews)) today"
    }

    private var remainingNewsItems: [WikipediaService.SearchResult] {
        feed.inTheNews
    }

    private var primaryTimelineEvents: [WikipediaService.DiscoverFeed.OnThisDayEvent] {
        if !feed.onThisDaySelected.isEmpty {
            return Array(feed.onThisDaySelected.prefix(8))
        }
        return Array(feed.onThisDay.prefix(8))
    }

    private var hasTimeMachineDetails: Bool {
        return !feed.onThisDayBirths.isEmpty || !feed.onThisDayDeaths.isEmpty || !feed.holidays.isEmpty
    }

    private var longestReadCandidates: [WikipediaService.SearchResult] {
        Array(allTimeMostReadStore.entries.prefix(allTimeMostReadLoadLimit).map(\.result))
    }

    private var wordCountLoadKey: String {
        longestReadCandidates.map(\.title).joined(separator: "|")
    }

    private var longestReadItems: [DiscoverLongestReadEntry] {
        let enriched = longestReadCandidates.compactMap { result -> DiscoverLongestReadEntry? in
            guard let wordCount = wordCountStore.wordCount(for: result.title), wordCount > 0 else {
                return nil
            }
            return DiscoverLongestReadEntry(result: result, wordCount: wordCount)
        }

        let sorted = enriched.sorted { lhs, rhs in
            if lhs.wordCount == rhs.wordCount {
                return lhs.result.title.localizedCaseInsensitiveCompare(rhs.result.title) == .orderedAscending
            }
            return lhs.wordCount > rhs.wordCount
        }

        return Array(sorted.prefix(playlistRowLimit))
    }

    private var longestFallbackItems: [WikipediaService.SearchResult] {
        Array(longestReadCandidates.prefix(min(playlistRowLimit, 6)))
    }

    private var keyboardMostReadResults: [WikipediaService.SearchResult] {
        playlistMostReadItems
    }

    private var keyboardLongestResults: [WikipediaService.SearchResult] {
        if !longestReadItems.isEmpty {
            return longestReadItems.map(\.result)
        }
        return longestFallbackItems
    }

    private var visibleKeyboardLanes: [DiscoverCollectionLane] {
        var lanes: [DiscoverCollectionLane] = []
        if showsMostReadCollection && !keyboardMostReadResults.isEmpty {
            lanes.append(.mostRead)
        }
        if showsLongestCollection && !keyboardLongestResults.isEmpty {
            lanes.append(.longest)
        }
        return lanes
    }

    private var collectionsFocusDataKey: String {
        let mostReadKey = keyboardMostReadResults.map(\.title).joined(separator: "|")
        let longestKey = keyboardLongestResults.map(\.title).joined(separator: "|")
        return "\(collectionsMode.rawValue)|\(mostReadKey)|\(longestKey)"
    }

    private var canOpenFocusedCollectionItem: Bool {
        guard isCollectionsKeyboardFocusActive else { return false }
        return focusedCollectionResult != nil
    }

    private func pageViewsRowKey(
        section: String,
        result: WikipediaService.SearchResult,
        index: Int? = nil
    ) -> String {
        let titleKey = ReadStateSync.normalizedTitle(result.title)
        if let index {
            return "\(section):\(index):\(result.id):\(titleKey)"
        }
        return "\(section):\(result.id):\(titleKey)"
    }

    private func presentPageViewsPopover(
        for result: WikipediaService.SearchResult,
        rowKey: String,
        initialPulse: WikipediaService.TrendPulse? = nil
    ) {
        activePageViewsPopover = DiscoverPageViewsPopoverPayload(
            rowKey: rowKey,
            title: result.title,
            initialPulse: initialPulse,
            referenceDate: trendReferenceDate
        )
    }

    private func pageViewsPopoverBinding(for rowKey: String) -> Binding<Bool> {
        Binding(
            get: { activePageViewsPopover?.rowKey == rowKey },
            set: { isPresented in
                guard !isPresented else { return }
                if activePageViewsPopover?.rowKey == rowKey {
                    activePageViewsPopover = nil
                }
            }
        )
    }

    @ViewBuilder
    private func pageViewsPopover(for rowKey: String) -> some View {
        if let payload = activePageViewsPopover, payload.rowKey == rowKey {
            DiscoverPageViewsPopoverContent(
                title: payload.title,
                referenceDate: payload.referenceDate,
                initialPulse: payload.initialPulse
            )
        }
    }

    private var focusedCollectionResult: WikipediaService.SearchResult? {
        switch focusedCollectionLane {
        case .mostRead:
            guard keyboardMostReadResults.indices.contains(focusedMostReadRowIndex) else { return nil }
            return keyboardMostReadResults[focusedMostReadRowIndex]
        case .longest:
            guard keyboardLongestResults.indices.contains(focusedLongestRowIndex) else { return nil }
            return keyboardLongestResults[focusedLongestRowIndex]
        }
    }

    private func rowCount(for lane: DiscoverCollectionLane) -> Int {
        switch lane {
        case .mostRead: return keyboardMostReadResults.count
        case .longest: return keyboardLongestResults.count
        }
    }

    private func focusedRowIndex(for lane: DiscoverCollectionLane) -> Int {
        switch lane {
        case .mostRead: return focusedMostReadRowIndex
        case .longest: return focusedLongestRowIndex
        }
    }

    private func setFocusedRowIndex(_ index: Int, for lane: DiscoverCollectionLane) {
        let upperBound = max(rowCount(for: lane) - 1, 0)
        let clamped = min(max(index, 0), upperBound)
        switch lane {
        case .mostRead:
            focusedMostReadRowIndex = clamped
        case .longest:
            focusedLongestRowIndex = clamped
        }
    }

    private func isFocusedCollectionRow(lane: DiscoverCollectionLane, index: Int) -> Bool {
        guard isCollectionsKeyboardFocusActive else { return false }
        guard focusedCollectionLane == lane else { return false }
        return focusedRowIndex(for: lane) == index
    }

    private func markCollectionsFocus(lane: DiscoverCollectionLane, index: Int) {
        focusedCollectionLane = lane
        setFocusedRowIndex(index, for: lane)
        isCollectionsKeyboardFocusActive = true
    }

    private func normalizeCollectionsKeyboardFocus() {
        let lanes = visibleKeyboardLanes
        guard !lanes.isEmpty else {
            isCollectionsKeyboardFocusActive = false
            focusedMostReadRowIndex = 0
            focusedLongestRowIndex = 0
            return
        }

        if !lanes.contains(focusedCollectionLane) {
            focusedCollectionLane = lanes.contains(.mostRead) ? .mostRead : lanes[0]
        }

        setFocusedRowIndex(focusedMostReadRowIndex, for: .mostRead)
        setFocusedRowIndex(focusedLongestRowIndex, for: .longest)
    }

    private func switchCollectionsModeForLane(direction: MoveCommandDirection) -> Bool {
        guard visibleKeyboardLanes.count <= 1 else { return false }
        guard direction == .left || direction == .right else { return false }

        switch (direction, collectionsMode) {
        case (.left, .longest):
            collectionsMode = .mostRead
            focusedCollectionLane = .mostRead
            normalizeCollectionsKeyboardFocus()
            return true
        case (.right, .mostRead):
            collectionsMode = .longest
            focusedCollectionLane = .longest
            normalizeCollectionsKeyboardFocus()
            return true
        default:
            return false
        }
    }

    private func shiftCollectionsFocusLane(_ direction: MoveCommandDirection) {
        if switchCollectionsModeForLane(direction: direction) {
            return
        }

        let lanes = visibleKeyboardLanes
        guard lanes.count > 1 else { return }
        guard let laneIndex = lanes.firstIndex(of: focusedCollectionLane) else {
            focusedCollectionLane = lanes[0]
            setFocusedRowIndex(0, for: lanes[0])
            return
        }

        let targetLaneIndex: Int
        if direction == .left {
            targetLaneIndex = max(laneIndex - 1, 0)
        } else if direction == .right {
            targetLaneIndex = min(laneIndex + 1, lanes.count - 1)
        } else {
            return
        }

        guard targetLaneIndex != laneIndex else { return }
        let targetLane = lanes[targetLaneIndex]
        let sourceIndex = focusedRowIndex(for: focusedCollectionLane)
        focusedCollectionLane = targetLane
        setFocusedRowIndex(sourceIndex, for: targetLane)
    }

    private func moveCollectionsFocus(_ direction: MoveCommandDirection) {
        guard !isSearchFieldFocused else { return }
        normalizeCollectionsKeyboardFocus()
        guard !visibleKeyboardLanes.isEmpty else { return }

        if !isCollectionsKeyboardFocusActive {
            isCollectionsKeyboardFocusActive = true
            if !visibleKeyboardLanes.contains(focusedCollectionLane) {
                focusedCollectionLane = visibleKeyboardLanes.contains(.mostRead) ? .mostRead : visibleKeyboardLanes[0]
            }
            if direction == .up {
                setFocusedRowIndex(max(rowCount(for: focusedCollectionLane) - 1, 0), for: focusedCollectionLane)
            } else if direction == .left || direction == .right {
                shiftCollectionsFocusLane(direction)
            }
            return
        }

        switch direction {
        case .up:
            let nextIndex = max(focusedRowIndex(for: focusedCollectionLane) - 1, 0)
            setFocusedRowIndex(nextIndex, for: focusedCollectionLane)
        case .down:
            let maxIndex = max(rowCount(for: focusedCollectionLane) - 1, 0)
            let nextIndex = min(focusedRowIndex(for: focusedCollectionLane) + 1, maxIndex)
            setFocusedRowIndex(nextIndex, for: focusedCollectionLane)
        case .left, .right:
            shiftCollectionsFocusLane(direction)
        default:
            break
        }
    }

    private func openFocusedCollectionItem(inNewTab: Bool) {
        guard let result = focusedCollectionResult else { return }
        onOpen(result, inNewTab)
    }

    @ViewBuilder
    private var collectionsKeyboardShortcutHost: some View {
        VStack(spacing: 0) {
            Button(action: { openFocusedCollectionItem(inNewTab: false) }) {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: [])

            Button(action: { openFocusedCollectionItem(inNewTab: true) }) {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0.001)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .disabled(!canOpenFocusedCollectionItem || isSearchFieldFocused)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: sectionSpacing) {
            if let featured = feed.featuredArticle {
                DiscoverSectionHeader(title: "Discover", subtitle: feed.dateLabel)
                let featuredRowKey = pageViewsRowKey(section: "featured", result: featured)
                DiscoverFeatureModule(
                    result: featured,
                    teaserText: featuredTeaserText,
                    isTeaserLoading: isFeaturedTeaserLoading,
                    visualContextImages: visualContextStore.images,
                    isVisualContextLoading: visualContextStore.isLoading && visualContextStore.images.isEmpty,
                    heroImageHeight: heroImageHeight,
                    titleLineLimit: isVeryCompactLayout ? 1 : 2,
                    descriptionLineLimit: isVeryCompactLayout ? 1 : 2,
                    isCompactLayout: isCompactLayout,
                    onOpen: onOpen,
                    onOpenURL: { url in
                        openURL(url)
                    }
                )
                .contextMenu {
                    discoverContextMenu(for: featured) {
                        presentPageViewsPopover(for: featured, rowKey: featuredRowKey)
                    }
                }
                .popover(isPresented: pageViewsPopoverBinding(for: featuredRowKey), arrowEdge: .trailing) {
                    pageViewsPopover(for: featuredRowKey)
                }
            }

            DiscoverSectionHeader(
                title: "Today’s Most Read",
                subtitle: "Daily chart kept separate from all-time collections"
            )
            DiscoverPlaylistColumn(
                title: "Today",
                subtitle: todayMostReadSubtitle,
                meta: todayMostReadMeta,
                systemImage: "sun.max.fill",
                tint: Color.blue.opacity(0.9),
                showsLoading: todayMostReadStore.isLoading || todayTrendPulseStore.isLoading,
                isKeyboardFocused: false
            ) {
                if todayMostReadItems.isEmpty {
                    DiscoverPlaylistPlaceholder(
                        text: todayMostReadStore.isLoading
                            ? "Loading today’s most read…"
                            : "Today’s Most Read is unavailable right now."
                    )
                } else {
                    ForEach(Array(todayMostReadItems.enumerated()), id: \.element.id) { index, result in
                        let rowKey = pageViewsRowKey(section: "today-most-read", result: result, index: index)
                        let trendPulse = todayMostReadPulse(for: result)
                        DiscoverPlaylistArticleRow(
                            result: result,
                            rank: index + 1,
                            primaryStat: todayMostReadPrimaryStat(for: result),
                            secondaryStat: todayMostReadSecondaryStat(for: result),
                            statTint: todayMostReadStatTint(for: result),
                            isKeyboardFocused: false,
                            onFocus: nil,
                            onOpen: onOpen
                        )
                        .contextMenu {
                            discoverContextMenu(for: result) {
                                presentPageViewsPopover(
                                    for: result,
                                    rowKey: rowKey,
                                    initialPulse: trendPulse
                                )
                            }
                        }
                        .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                            pageViewsPopover(for: rowKey)
                        }
                    }
                }
            }

            if !feed.newsStories.isEmpty {
                DiscoverSectionHeader(title: "News Briefing", subtitle: "Editorial context from today’s feed")
                VStack(spacing: 10) {
                    ForEach(feed.newsStories.prefix(newsBriefingLimit)) { story in
                        DiscoverNewsStoryCard(
                            story: story,
                            onOpen: onOpen,
                            referenceDate: trendReferenceDate
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 12) {
                    DiscoverSectionHeader(
                        title: "Collections",
                        subtitle: "A playful pair: what everyone reads and what rewards a long sit"
                    )
                    Spacer(minLength: 8)
                    collectionsModeControl
                }
            }

            LazyVGrid(columns: playlistColumns, spacing: 12) {
                if showsMostReadCollection {
                    DiscoverPlaylistColumn(
                        title: "Most Read",
                        subtitle: playlistMostReadSubtitle,
                        meta: mostReadCollectionMeta,
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: .accentColor,
                        showsLoading: trendPulseStore.isLoading,
                        isKeyboardFocused: isCollectionsKeyboardFocusActive && focusedCollectionLane == .mostRead
                    ) {
                        if playlistMostReadItems.isEmpty {
                            DiscoverPlaylistPlaceholder(
                                text: allTimeMostReadStore.isLoading
                                    ? "Loading all-time most read…"
                                    : "All-time Most Read is unavailable right now."
                            )
                        } else {
                            ForEach(Array(playlistMostReadItems.enumerated()), id: \.element.id) { index, result in
                                let rowKey = pageViewsRowKey(section: "collection-most-read", result: result, index: index)
                                let trendPulse = trendPulseStore.pulse(for: result.title)
                                DiscoverPlaylistArticleRow(
                                    result: result,
                                    rank: index + 1,
                                    primaryStat: mostReadPrimaryStat(for: result),
                                    secondaryStat: mostReadSecondaryStat(for: result),
                                    statTint: mostReadStatTint(for: result),
                                    isKeyboardFocused: isFocusedCollectionRow(lane: .mostRead, index: index),
                                    onFocus: {
                                        markCollectionsFocus(lane: .mostRead, index: index)
                                    },
                                    onOpen: onOpen
                                )
                                    .contextMenu {
                                        discoverContextMenu(for: result) {
                                            presentPageViewsPopover(
                                                for: result,
                                                rowKey: rowKey,
                                                initialPulse: trendPulse
                                            )
                                        }
                                    }
                                    .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                                        pageViewsPopover(for: rowKey)
                                    }
                            }
                        }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                if showsLongestCollection {
                    DiscoverPlaylistColumn(
                        title: "Longest Reads",
                        subtitle: playlistLongestSubtitle,
                        meta: longestCollectionMeta,
                        systemImage: "text.alignleft",
                        tint: Color.orange.opacity(0.9),
                        showsLoading: wordCountStore.isLoading,
                        isKeyboardFocused: isCollectionsKeyboardFocusActive && focusedCollectionLane == .longest
                    ) {
                        if longestReadItems.isEmpty {
                            if longestFallbackItems.isEmpty {
                                DiscoverPlaylistPlaceholder(
                                    text: wordCountStore.isLoading
                                        ? "Finding long reads…"
                                        : "No all-time long-read candidates are available yet."
                                )
                            } else {
                                ForEach(Array(longestFallbackItems.enumerated()), id: \.element.id) { index, result in
                                    let rowKey = pageViewsRowKey(section: "collection-longest-fallback", result: result, index: index)
                                    DiscoverPlaylistArticleRow(
                                        result: result,
                                        rank: index + 1,
                                        primaryStat: wordCountStore.isLoading ? "Loading words…" : "Word count unavailable",
                                        secondaryStat: wordCountStore.isLoading ? nil : "Open to inspect",
                                        statTint: .secondary,
                                        isKeyboardFocused: isFocusedCollectionRow(lane: .longest, index: index),
                                        onFocus: {
                                            markCollectionsFocus(lane: .longest, index: index)
                                        },
                                        onOpen: onOpen
                                    )
                                        .contextMenu {
                                            discoverContextMenu(for: result) {
                                                presentPageViewsPopover(for: result, rowKey: rowKey)
                                            }
                                        }
                                        .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                                            pageViewsPopover(for: rowKey)
                                        }
                                }
                            }
                        } else {
                            ForEach(Array(longestReadItems.enumerated()), id: \.element.id) { index, entry in
                                let rowKey = pageViewsRowKey(section: "collection-longest", result: entry.result, index: index)
                                DiscoverPlaylistArticleRow(
                                    result: entry.result,
                                    rank: index + 1,
                                    primaryStat: formattedWordCount(entry.wordCount),
                                    secondaryStat: estimatedReadingTimeText(for: entry.wordCount),
                                    statTint: Color.orange.opacity(0.92),
                                    isKeyboardFocused: isFocusedCollectionRow(lane: .longest, index: index),
                                    onFocus: {
                                        markCollectionsFocus(lane: .longest, index: index)
                                    },
                                    onOpen: onOpen
                                )
                                    .contextMenu {
                                        discoverContextMenu(for: entry.result) {
                                            presentPageViewsPopover(for: entry.result, rowKey: rowKey)
                                        }
                                    }
                                    .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                                        pageViewsPopover(for: rowKey)
                                    }
                            }
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(
                reduceMotion ? nil : .interactiveSpring(response: 0.34, dampingFraction: 0.86),
                value: collectionsMode
            )

            if let featuredImage = feed.featuredImage {
                DiscoverSectionHeader(title: "Image of the Day", subtitle: "From Wikimedia Commons")
                DiscoverFeaturedImageCard(image: featuredImage)
            }

            if !remainingNewsItems.isEmpty {
                DiscoverSectionHeader(title: "In the News", subtitle: "Live events across Wikipedia")
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(remainingNewsItems.prefix(12)) { result in
                            let rowKey = pageViewsRowKey(section: "in-news", result: result)
                            DiscoverNewsCard(result: result, onOpen: onOpen)
                                .frame(width: 230)
                                .contextMenu {
                                    discoverContextMenu(for: result) {
                                        presentPageViewsPopover(for: result, rowKey: rowKey)
                                    }
                                }
                                .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                                    pageViewsPopover(for: rowKey)
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }

            DiscoverSectionHeader(title: "Time Capsule", subtitle: "Anniversaries and curious facts")
            HStack(alignment: .top, spacing: isCompactLayout ? 10 : 12) {
                if !primaryTimelineEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This Day in History")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(primaryTimelineEvents) { event in
                            DiscoverOnThisDayRow(
                                event: event,
                                onOpen: onOpen,
                                referenceDate: trendReferenceDate
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                if !feed.didYouKnow.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Did You Know?")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(feed.didYouKnow.prefix(8)) { fact in
                            DiscoverDidYouKnowRow(
                                fact: fact,
                                onOpen: onOpen,
                                referenceDate: trendReferenceDate
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            if hasTimeMachineDetails {
                DiscoverSectionHeader(title: "Time Machine", subtitle: "Births, deaths, and observances on this date")
                VStack(alignment: .leading, spacing: 12) {
                    if !feed.onThisDayBirths.isEmpty || !feed.onThisDayDeaths.isEmpty {
                        HStack(alignment: .top, spacing: isCompactLayout ? 10 : 12) {
                            if !feed.onThisDayBirths.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Born")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)

                                    ForEach(feed.onThisDayBirths.prefix(6)) { event in
                                        DiscoverOnThisDayRow(
                                            event: event,
                                            onOpen: onOpen,
                                            referenceDate: trendReferenceDate
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }

                            if !feed.onThisDayDeaths.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Died")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)

                                    ForEach(feed.onThisDayDeaths.prefix(6)) { event in
                                        DiscoverOnThisDayRow(
                                            event: event,
                                            onOpen: onOpen,
                                            referenceDate: trendReferenceDate
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                    }

                    if !feed.holidays.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Holidays & Observances")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(feed.holidays.prefix(8)) { holiday in
                                DiscoverHolidayRow(
                                    holiday: holiday,
                                    onOpen: onOpen,
                                    referenceDate: trendReferenceDate
                                )
                            }
                        }
                    }
                }
            }
        }
        .background {
            collectionsKeyboardShortcutHost
        }
        .onAppear {
            normalizeCollectionsKeyboardFocus()
        }
        .onChange(of: feed.dateKey) { _, _ in
            activePageViewsPopover = nil
        }
        .onChange(of: collectionsFocusDataKey) { _, _ in
            normalizeCollectionsKeyboardFocus()
        }
        .onChange(of: isSearchFieldFocused) { _, focused in
            if focused {
                isCollectionsKeyboardFocusActive = false
            }
        }
        .onMoveCommand { direction in
            moveCollectionsFocus(direction)
        }
        .onExitCommand {
            isCollectionsKeyboardFocusActive = false
        }
        .task(id: todayMostReadLoadKey) {
            todayMostReadStore.queueLoad(forceRefresh: refreshGeneration > 0)
        }
        .task(id: allTimeMostReadLoadKey) {
            allTimeMostReadStore.queueLoad(limit: allTimeMostReadLoadLimit)
        }
        .task(id: todayTrendPulseLoadKey) {
            todayTrendPulseStore.queueLoad(
                results: todayMostReadItems,
                referenceDate: mostReadPulseReferenceDate
            )
        }
        .task(id: trendPulseLoadKey) {
            trendPulseStore.queueLoad(
                results: playlistMostReadItems,
                referenceDate: mostReadPulseReferenceDate
            )
        }
        .task(id: wordCountLoadKey) {
            wordCountStore.queueLoad(results: longestReadCandidates)
        }
        .task(id: featuredArticleTitle) {
            featuredSummaryStore.queueLoad(featuredTitle: featuredArticleTitle)
            visualContextStore.queueLoad(featuredTitle: featuredArticleTitle)
        }
        .onDisappear {
            todayMostReadStore.cancel()
            todayTrendPulseStore.cancel()
            allTimeMostReadStore.cancel()
            trendPulseStore.cancel()
            wordCountStore.cancel()
            featuredSummaryStore.cancel()
            visualContextStore.cancel()
        }
    }

    private func mostReadPulse(for result: WikipediaService.SearchResult) -> WikipediaService.TrendPulse? {
        trendPulseStore.pulse(for: result.title)
    }

    private func todayMostReadPulse(for result: WikipediaService.SearchResult) -> WikipediaService.TrendPulse? {
        todayTrendPulseStore.pulse(for: result.title)
    }

    private func allTimeMostReadEntry(
        for result: WikipediaService.SearchResult
    ) -> WikipediaService.AllTimeMostReadEntry? {
        allTimeMostReadByTitleKey[ReadStateSync.normalizedTitle(result.title)]
    }

    private func mostReadPrimaryStat(for result: WikipediaService.SearchResult) -> String {
        if let allTimeViews = allTimeMostReadEntry(for: result)?.totalViews {
            return "\(abbreviatedViewCount(allTimeViews)) all-time"
        }
        guard let pulse = mostReadPulse(for: result) else {
            return trendPulseStore.isLoading ? "All-time loading…" : "All-time unavailable"
        }
        return "\(abbreviatedViewCount(pulse.latestViews)) views"
    }

    private func mostReadSecondaryStat(for result: WikipediaService.SearchResult) -> String? {
        guard let pulse = mostReadPulse(for: result) else {
            return trendPulseStore.isLoading ? "Loading recent pulse…" : "Recent pulse unavailable"
        }
        guard let fraction = trendDeltaFraction(for: pulse) else { return "No delta yet" }

        let percent = fraction * 100
        let sign = percent > 0 ? "+" : ""
        return "\(sign)\(percent.formatted(.number.precision(.fractionLength(0...1))))% recent"
    }

    private func mostReadStatTint(for result: WikipediaService.SearchResult) -> Color {
        guard let pulse = mostReadPulse(for: result),
              let fraction = trendDeltaFraction(for: pulse) else {
            return .secondary
        }

        if fraction > 0 { return Color.green.opacity(0.85) }
        if fraction < 0 { return Color.red.opacity(0.8) }
        return .secondary
    }

    private func todayMostReadPrimaryStat(for result: WikipediaService.SearchResult) -> String {
        guard let pulse = todayMostReadPulse(for: result) else {
            return todayTrendPulseStore.isLoading ? "Views loading…" : "Views unavailable"
        }
        return "\(abbreviatedViewCount(pulse.latestViews)) views"
    }

    private func todayMostReadSecondaryStat(for result: WikipediaService.SearchResult) -> String? {
        guard let pulse = todayMostReadPulse(for: result) else {
            return todayTrendPulseStore.isLoading ? nil : "No trend data"
        }
        guard let fraction = trendDeltaFraction(for: pulse) else { return "No delta yet" }

        let percent = fraction * 100
        let sign = percent > 0 ? "+" : ""
        return "\(sign)\(percent.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    private func todayMostReadStatTint(for result: WikipediaService.SearchResult) -> Color {
        guard let pulse = todayMostReadPulse(for: result),
              let fraction = trendDeltaFraction(for: pulse) else {
            return .secondary
        }

        if fraction > 0 { return Color.green.opacity(0.85) }
        if fraction < 0 { return Color.red.opacity(0.8) }
        return .secondary
    }

    private func trendDeltaFraction(for pulse: WikipediaService.TrendPulse) -> Double? {
        guard let previous = pulse.previousViews, previous > 0 else { return nil }
        return Double(pulse.latestViews - previous) / Double(previous)
    }

    private func formattedWordCount(_ wordCount: Int) -> String {
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: wordCount), number: .decimal)
        return "\(formatted) words"
    }

    private func estimatedReadingTimeText(for wordCount: Int) -> String {
        let minutes = estimatedReadingMinutes(for: wordCount)
        return "\(minutes) min read"
    }

    private func estimatedReadingMinutes(for wordCount: Int) -> Int {
        let wordsPerMinute = 220.0
        return max(1, Int((Double(wordCount) / wordsPerMinute).rounded(.up)))
    }

    private func formattedReadingDuration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainderMinutes = minutes % 60
        if remainderMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainderMinutes)m"
    }

    @ViewBuilder
    private var collectionsModeControl: some View {
        if usesSegmentedCollectionsControl {
            Picker("Collection focus", selection: $collectionsMode) {
                ForEach(DiscoverCollectionsMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: collectionsControlWidth)
            .accessibilityLabel("Collection focus")
        } else {
            Menu {
                ForEach(DiscoverCollectionsMode.allCases) { mode in
                    Button {
                        collectionsMode = mode
                    } label: {
                        SwiftUI.Label(mode.title, systemImage: mode.systemImage)
                    }
                }
            } label: {
                SwiftUI.Label(collectionsMode.title, systemImage: collectionsMode.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                    }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private static let featuredFeedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    @ViewBuilder
    private func discoverContextMenu(
        for result: WikipediaService.SearchResult,
        onShowPageViews: (() -> Void)? = nil
    ) -> some View {
        Button {
            onOpen(result, false)
        } label: {
            SwiftUI.Label("Open", systemImage: "doc.text")
        }

        Button {
            onOpen(result, true)
        } label: {
            SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
        }

        if let onShowPageViews {
            Button {
                onShowPageViews()
            } label: {
                SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
            }
        }

        Divider()

        Button {
            copyToClipboard(result.title)
        } label: {
            SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
        }

        Button {
            copyToClipboard(wikipediaURLString(for: result.title))
        } label: {
            SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
        }
    }

    private func copyToClipboard(_ value: String) {
        _ = SystemBridge.copyText(value)
    }

    private func wikipediaURLString(for title: String) -> String {
        WikipediaURLBuilder.articleURLString(forTitle: title)
    }
}

private struct DiscoverSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DiscoverTypography.sectionTitle)
            Text(subtitle)
                .font(DiscoverTypography.sectionSubtitle)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DiscoverLongestReadEntry: Identifiable {
    let result: WikipediaService.SearchResult
    let wordCount: Int

    var id: String {
        "\(result.id)-\(result.title.lowercased().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

private struct DiscoverPlaylistColumn<Content: View>: View {
    let title: String
    let subtitle: String
    let meta: String?
    let systemImage: String
    let tint: Color
    let showsLoading: Bool
    let isKeyboardFocused: Bool
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    init(
        title: String,
        subtitle: String,
        meta: String? = nil,
        systemImage: String,
        tint: Color,
        showsLoading: Bool = false,
        isKeyboardFocused: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.systemImage = systemImage
        self.tint = tint
        self.showsLoading = showsLoading
        self.isKeyboardFocused = isKeyboardFocused
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 19, height: 19)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let meta, !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                if showsLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 1)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                content
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isKeyboardFocused
                        ? tint.opacity(0.48)
                        : Color.primary.opacity(isHovered ? 0.12 : 0.07),
                    lineWidth: isKeyboardFocused ? 1.1 : 0.8
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [tint.opacity(0.18), Color.primary.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        }
        .scaleEffect(reduceMotion ? 1 : ((isHovered || isKeyboardFocused) ? 1.004 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isKeyboardFocused)
        .onHover { isHovered = $0 }
    }
}

private struct DiscoverPlaylistPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DiscoverInteractivePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.985
    var pressedOpacity: Double = 0.93

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? pressedScale : 1))
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

private struct DiscoverPlaylistArticleRow: View {
    let result: WikipediaService.SearchResult
    let rank: Int
    let primaryStat: String
    let secondaryStat: String?
    let statTint: Color
    let isKeyboardFocused: Bool
    let onFocus: (() -> Void)?
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            onFocus?()
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text("\(rank)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)

                DiscoverThumbnailSlot(
                    thumbnailURL: result.thumbnailURL,
                    size: 46,
                    cornerRadius: 8,
                    imagePadding: 3
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(2)
                    if let description = result.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 1.5) {
                    Text(primaryStat)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(statTint)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .monospacedDigit()

                    if let secondaryStat, !secondaryStat.isEmpty {
                        Text(secondaryStat)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isKeyboardFocused
                            ? statTint.opacity(0.16)
                            : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isKeyboardFocused
                            ? statTint.opacity(0.55)
                            : Color.primary.opacity(isHovered ? 0.14 : 0),
                        lineWidth: isKeyboardFocused ? 1.05 : 0.8
                    )
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .scaleEffect(reduceMotion ? 1 : ((isHovered || isKeyboardFocused) ? 1.005 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isKeyboardFocused)
        .accessibilityLabel(result.title)
        .accessibilityValue(secondaryStat.map { "\(primaryStat), \($0)" } ?? primaryStat)
        .accessibilityHint("Open article. Use arrows to move focus and Return to open.")
    }
}

private enum DiscoverTypography {
    static let sectionTitle = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let sectionSubtitle = Font.system(size: 11, weight: .regular)
    static let featureTitle = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let featureDescription = Font.system(size: 12.5, weight: .regular)
    static let newsCardTitle = Font.system(size: 13.5, weight: .semibold, design: .rounded)
    static let newsCardDescription = Font.system(size: 11.5, weight: .regular)
    static let compactRank = Font.system(size: 14.5, weight: .semibold, design: .rounded)
    static let compactTitle = Font.system(size: 12.5, weight: .medium)
    static let compactDescription = Font.system(size: 11, weight: .regular)
    static let storyBody = Font.system(size: 12.5, weight: .regular)
    static let mediaTitle = Font.system(size: 16.5, weight: .semibold, design: .rounded)
    static let mediaDescription = Font.system(size: 12.5, weight: .regular)
    static let mediaMeta = Font.system(size: 11.5, weight: .medium)
}

private struct DiscoverFeatureModule: View {
    let result: WikipediaService.SearchResult
    let teaserText: String?
    let isTeaserLoading: Bool
    let visualContextImages: [WikipediaService.VisualContextImage]
    let isVisualContextLoading: Bool
    let heroImageHeight: CGFloat
    let titleLineLimit: Int
    let descriptionLineLimit: Int
    let isCompactLayout: Bool
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiscoverFeatureCard(
                result: result,
                teaserText: teaserText,
                isTeaserLoading: isTeaserLoading,
                heroImageHeight: heroImageHeight,
                titleLineLimit: titleLineLimit,
                descriptionLineLimit: descriptionLineLimit,
                onOpen: onOpen,
                showsSurface: false
            )
            .padding(12)

            Divider()
                .overlay(Color.primary.opacity(0.05))

            Group {
                if isVisualContextLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading visual context…")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                } else if !visualContextImages.isEmpty {
                    DiscoverVisualContextStrip(
                        images: visualContextImages,
                        isCompactLayout: isCompactLayout,
                        showsSurface: false,
                        onOpenURL: onOpenURL
                    )
                    .padding(12)
                } else {
                    Text("Visual context isn’t available for this article yet.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.9)
        }
    }
}

private struct DiscoverFeatureCard: View {
    let result: WikipediaService.SearchResult
    let teaserText: String?
    let isTeaserLoading: Bool
    let heroImageHeight: CGFloat
    let titleLineLimit: Int
    let descriptionLineLimit: Int
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    var showsSurface: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var imageTransaction: Transaction {
        reduceMotion ? Transaction(animation: nil) : Transaction(animation: .easeOut(duration: 0.18))
    }

    private var displayTitle: String {
        let trimmed = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Featured Story" : trimmed
    }

    private var displayDescription: String? {
        guard let description = result.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty else {
            return nil
        }
        return description
    }

    var body: some View {
        Button {
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    featureImage
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.05),
                            Color.black.opacity(0.24)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    Text("Featured")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.18), in: Capsule())
                        .padding(14)
                }
                .frame(maxWidth: .infinity)
                .frame(height: heroImageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayTitle)
                        .font(DiscoverTypography.featureTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(titleLineLimit)
                        .lineSpacing(1.4)

                    if let displayDescription {
                        Text(displayDescription)
                            .font(DiscoverTypography.featureDescription)
                            .foregroundStyle(.secondary)
                            .lineLimit(descriptionLineLimit)
                            .lineSpacing(1.2)
                    }

                    if isTeaserLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading article teaser…")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.top, 2)
                    } else if let teaserText, !teaserText.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(teaserText)
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(8)
                                .lineSpacing(1.25)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(12)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(displayTitle)
        .frame(minHeight: heroImageHeight + 72)
        .background(
            Group {
                if showsSurface {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if showsSurface {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.16 : 0.08), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.12 : 0.04), lineWidth: 0.8)
            }
        }
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.005 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var featureImage: some View {
        if let thumbnailURL = result.thumbnailURL {
            AsyncImage(
                url: thumbnailURL,
                transaction: imageTransaction
            ) { phase in
                switch phase {
                case .success(let image):
                    ZStack {
                        Rectangle()
                            .fill(Color.primary.opacity(0.04))
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(.horizontal, 8)
                    }
                    .transition(.opacity)
                case .failure:
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.25), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                default:
                    Rectangle()
                        .fill(.quaternary)
                }
            }
        } else {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.25), Color.blue.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct DiscoverNewsCard: View {
    let result: WikipediaService.SearchResult
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var imageTransaction: Transaction {
        reduceMotion ? Transaction(animation: nil) : Transaction(animation: .easeOut(duration: 0.18))
    }

    var body: some View {
        Button {
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let thumbnailURL = result.thumbnailURL {
                    AsyncImage(
                        url: thumbnailURL,
                        transaction: imageTransaction
                    ) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                        case .success(let image):
                            ZStack {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.04))
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(6)
                            }
                            .transition(.opacity)
                        case .failure:
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                        @unknown default:
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text(result.title)
                    .font(DiscoverTypography.newsCardTitle)
                    .lineLimit(2)
                    .lineSpacing(1.2)
                if let description = result.description {
                    Text(description)
                        .font(DiscoverTypography.newsCardDescription)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .lineSpacing(1.1)
                }
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(result.title)
        .padding(11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.16 : 0.08), lineWidth: 0.8)
        }
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.01 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DiscoverCompactArticleCard: View {
    let result: WikipediaService.SearchResult
    let rank: Int
    let trendPulse: WikipediaService.TrendPulse?
    var onTrendTapped: ((WikipediaService.TrendPulse) -> Void)? = nil
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @State private var suppressPrimaryTapFromTrend = false

    var body: some View {
        Button {
            if suppressPrimaryTapFromTrend {
                suppressPrimaryTapFromTrend = false
                return
            }
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            HStack(spacing: 9) {
                Text("\(rank)")
                    .font(DiscoverTypography.compactRank)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .leading)

                DiscoverThumbnailSlot(
                    thumbnailURL: result.thumbnailURL,
                    size: 62,
                    cornerRadius: 8,
                    imagePadding: 4
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(DiscoverTypography.compactTitle)
                        .lineLimit(2)
                        .lineSpacing(1.05)
                    if let description = result.description {
                        Text(description)
                            .font(DiscoverTypography.compactDescription)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(1.0)
                    }
                    if let trendPulse {
                        DiscoverTrendPulseBadge(
                            pulse: trendPulse,
                            onTap: {
                                suppressPrimaryTapFromTrend = true
                                onTrendTapped?(trendPulse)
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 700_000_000)
                                    suppressPrimaryTapFromTrend = false
                                }
                            }
                        )
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(result.title)
        .padding(9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DiscoverTrendPulseBadge: View {
    let pulse: WikipediaService.TrendPulse
    var onTap: (() -> Void)? = nil

    private var deltaFraction: Double? {
        guard let previous = pulse.previousViews, previous > 0 else { return nil }
        return (Double(pulse.latestViews - previous) / Double(previous))
    }

    private var deltaText: String {
        guard let deltaFraction else { return "No delta" }
        let percent = deltaFraction * 100
        let sign = percent > 0 ? "+" : ""
        return "\(sign)\(percent.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    private var trendColor: Color {
        guard let deltaFraction else { return .secondary }
        if deltaFraction > 0 { return Color.green.opacity(0.85) }
        if deltaFraction < 0 { return Color.red.opacity(0.8) }
        return .secondary
    }

    private var latestViewsText: String {
        abbreviatedViewCount(pulse.latestViews)
    }

    var body: some View {
        HStack(spacing: 6) {
            DiscoverSparkline(points: pulse.points, tint: trendColor)
                .frame(width: 64, height: 16)

            Text(deltaText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(trendColor)
                .lineLimit(1)

            Text("\(latestViewsText) views")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Capsule())
        .highPriorityGesture(
            TapGesture().onEnded {
                onTap?()
            }
        )
        .help("Show views details")
    }
}

private struct DiscoverPageViewsPopoverPayload {
    let rowKey: String
    let title: String
    let initialPulse: WikipediaService.TrendPulse?
    let referenceDate: Date
}

private struct DiscoverPageViewsPopoverContent: View {
    let title: String
    let referenceDate: Date
    let initialPulse: WikipediaService.TrendPulse?

    @State private var pulse: WikipediaService.TrendPulse?
    @State private var isLoading = false
    @State private var didFailLoad = false
    @State private var selectedRange: ViewsPopoverTimeRange

    init(
        title: String,
        referenceDate: Date,
        initialPulse: WikipediaService.TrendPulse? = nil
    ) {
        self.title = title
        self.referenceDate = referenceDate
        self.initialPulse = initialPulse
        _pulse = State(initialValue: initialPulse)
        _selectedRange = State(initialValue: ViewsPopoverTimeRange.matching(days: initialPulse?.points.count ?? 30))
    }

    private var requestedDays: Int {
        selectedRange.requestedDays(relativeTo: referenceDate)
    }

    private var loadKey: String {
        let normalizedTitle = title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let endStamp = Int(referenceDate.timeIntervalSinceReferenceDate)
        return "\(normalizedTitle)|\(endStamp)|\(selectedRange.rawValue)|\(requestedDays)"
    }

    var body: some View {
        Group {
            if let pulse {
                TrendPulsePopoverView(title: title, pulse: pulse, selectedRange: $selectedRange)
            } else if isLoading {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Views")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading page views…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(width: 300, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Views")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                    Text(didFailLoad ? "Page views are unavailable for this article right now." : "No pageview data yet.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task {
                            await loadPulse()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(14)
                .frame(width: 300, alignment: .leading)
            }
        }
        .task(id: loadKey) {
            await loadPulseIfNeeded()
        }
    }

    @MainActor
    private func loadPulseIfNeeded() async {
        await loadPulse()
    }

    @MainActor
    private func loadPulse() async {
        isLoading = true
        didFailLoad = false
        defer { isLoading = false }

        do {
            let fetched = try await WikipediaService.shared.fetchTrendPulse(
                for: title,
                referenceDate: referenceDate,
                days: requestedDays
            )
            guard !Task.isCancelled else { return }
            pulse = fetched
        } catch {
            guard !Task.isCancelled else { return }
            didFailLoad = true
        }
    }
}

private struct DiscoverSparkline: View {
    let points: [Int]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let minValue = CGFloat(points.min() ?? 0)
            let maxValue = CGFloat(points.max() ?? 1)
            let range = max(maxValue - minValue, 1)
            let count = max(points.count, 2)

            let chartPoints: [CGPoint] = points.enumerated().map { index, value in
                let x = (CGFloat(index) / CGFloat(count - 1)) * width
                let normalizedY = (CGFloat(value) - minValue) / range
                let y = height - (normalizedY * height)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: width, y: height))
                }
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1))

                if chartPoints.count >= 2 {
                    Path { path in
                        path.move(to: chartPoints[0])
                        for point in chartPoints.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }

                if let last = chartPoints.last {
                    Circle()
                        .fill(tint)
                        .frame(width: 3.5, height: 3.5)
                        .position(last)
                }
            }
        }
    }
}

private struct DiscoverVisualContextStrip: View {
    let images: [WikipediaService.VisualContextImage]
    let isCompactLayout: Bool
    var showsSurface: Bool = true
    let onOpenURL: (URL) -> Void

    private var cardWidth: CGFloat {
        isCompactLayout ? 168 : 194
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Visual Context")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                Text("From this article’s media")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(images) { image in
                        DiscoverVisualContextCard(
                            image: image,
                            onOpenURL: onOpenURL
                        )
                        .frame(width: cardWidth)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }

        if showsSurface {
            content
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
                }
        } else {
            content
        }
    }
}

private struct DiscoverVisualContextCard: View {
    let image: WikipediaService.VisualContextImage
    let onOpenURL: (URL) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var imageTransaction: Transaction {
        reduceMotion ? Transaction(animation: nil) : Transaction(animation: .easeOut(duration: 0.18))
    }

    private var displayTitle: String {
        var cleaned = image.mediaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("file:") {
            cleaned = String(cleaned.dropFirst("file:".count))
        }
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        cleaned = cleaned.replacingOccurrences(
            of: #"\.(jpe?g|png|gif|webp|tiff?|svg)$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Media image" : cleaned
    }

    var body: some View {
        Button {
            if let filePageURL = image.filePageURL {
                onOpenURL(filePageURL)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: image.thumbnailURL, transaction: imageTransaction) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                            }
                    case .success(let loadedImage):
                        loadedImage
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                            }
                    @unknown default:
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(displayTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(2)

                if let caption = image.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .disabled(image.filePageURL == nil)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.13 : 0.05), lineWidth: 0.8)
        }
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.01 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct DiscoverThumbnailSlot: View {
    let thumbnailURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    let imagePadding: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var imageTransaction: Transaction {
        reduceMotion ? Transaction(animation: nil) : Transaction(animation: .easeOut(duration: 0.18))
    }

    var body: some View {
        Group {
            if let thumbnailURL {
                AsyncImage(url: thumbnailURL, transaction: imageTransaction) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                            }
                    case .success(let image):
                        ZStack {
                            Rectangle()
                                .fill(Color.primary.opacity(0.04))
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(imagePadding)
                        }
                        .transition(.opacity)
                    case .failure:
                        emptySlot
                    @unknown default:
                        emptySlot
                    }
                }
            } else {
                emptySlot
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var emptySlot: some View {
        Color.clear
    }
}

private struct DiscoverFeaturedImageCard: View {
    let image: WikipediaService.DiscoverFeed.FeaturedImage
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var imageTransaction: Transaction {
        reduceMotion ? Transaction(animation: nil) : Transaction(animation: .easeOut(duration: 0.18))
    }

    private var displayImageURL: URL? {
        image.thumbnailURL ?? image.imageURL
    }

    private var displayTitle: String {
        let rawTitle = image.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else { return "Image of the Day" }

        var cleaned = rawTitle
        if cleaned.lowercased().hasPrefix("file:") {
            cleaned = String(cleaned.dropFirst("file:".count))
        }
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        cleaned = cleaned.replacingOccurrences(
            of: #"\.(jpe?g|png|gif|webp|tiff?|svg)$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? rawTitle : cleaned
    }

    private var displayDescription: String? {
        guard let description = image.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty else {
            return nil
        }
        return description
    }

    private var creditsText: String? {
        let pieces = [image.artist, image.credit]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else { return nil }

        var seen = Set<String>()
        let uniquePieces = pieces.filter { piece in
            let key = piece.lowercased()
            let inserted = seen.insert(key).inserted
            return inserted
        }
        guard !uniquePieces.isEmpty else { return nil }
        return uniquePieces.joined(separator: " \u{00B7} ")
    }

    private var licenseText: String? {
        switch (image.licenseName, image.licenseCode) {
        case let (.some(name), .some(code)):
            return "\(name) (\(code))"
        case let (.some(name), nil):
            return name
        case let (nil, .some(code)):
            return code
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let displayImageURL {
                    AsyncImage(
                        url: displayImageURL,
                        transaction: imageTransaction
                    ) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                        case .success(let loadedImage):
                            ZStack {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.04))
                                loadedImage
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(8)
                            }
                            .transition(.opacity)
                        case .failure:
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                        @unknown default:
                            Rectangle().fill(.quaternary)
                        }
                    }
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle)
                    .font(DiscoverTypography.mediaTitle)
                    .lineLimit(3)
                    .lineSpacing(1.2)

                if let displayDescription {
                    Text(displayDescription)
                        .font(DiscoverTypography.mediaDescription)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .lineSpacing(1.2)
                }

                if let creditsText, !creditsText.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(creditsText)
                            .font(DiscoverTypography.mediaMeta)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                HStack(spacing: 8) {
                    if let filePageURL = image.filePageURL {
                        Button {
                            openURL(filePageURL)
                        } label: {
                            SwiftUI.Label("View on Commons", systemImage: "arrow.up.right.square")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.quaternary.opacity(0.6), in: Capsule())
                        }
                        .buttonStyle(DiscoverInteractivePressStyle())
                    }

                    if let licenseText {
                        Text(licenseText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.quaternary.opacity(0.5), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.16 : 0.08), lineWidth: 0.8)
        }
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.004 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button {
                _ = SystemBridge.copyText(displayTitle)
            } label: {
                SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
            }

            if let filePageURL = image.filePageURL {
                Button {
                    _ = SystemBridge.copyText(filePageURL.absoluteString)
                } label: {
                    SwiftUI.Label("Copy Commons Link", systemImage: "link")
                }
            }
        }
    }
}

private struct DiscoverNewsStoryCard: View {
    let story: WikipediaService.DiscoverFeed.NewsStory
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let referenceDate: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activePageViewsTitle: String?
    @State private var isHovered = false

    private var renderedStory: AttributedString {
        let cleaned = Self.sanitizedStoryText(story.story)
        return AttributedString(cleaned)
    }

    private static func sanitizedStoryText(_ storyText: String) -> String {
        let raw = storyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        return stripMarkdownLinksPreservingLabels(in: raw)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips Markdown link wrappers (`[label](url)`) while preserving label text.
    /// Handles URLs that contain nested parentheses.
    private static func stripMarkdownLinksPreservingLabels(in text: String) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "[" else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            guard let closingBracket = text[index...].firstIndex(of: "]") else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            let afterBracket = text.index(after: closingBracket)
            guard afterBracket < text.endIndex, text[afterBracket] == "(" else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            let labelStart = text.index(after: index)
            let label = text[labelStart..<closingBracket]

            var cursor = text.index(after: afterBracket)
            var depth = 1
            while cursor < text.endIndex && depth > 0 {
                switch text[cursor] {
                case "(":
                    depth += 1
                case ")":
                    depth -= 1
                default:
                    break
                }
                cursor = text.index(after: cursor)
            }

            guard depth == 0 else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            output.append(contentsOf: label)
            index = cursor
        }

        return output
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !story.story.isEmpty {
                Text(renderedStory)
                    .font(DiscoverTypography.storyBody)
                    .lineSpacing(1.3)
                    .lineLimit(3)
            }

            if !story.links.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(story.links.prefix(5)) { link in
                            DiscoverStoryLinkChip(
                                link: link,
                                onOpen: onOpen,
                                referenceDate: referenceDate,
                                activePageViewsTitle: $activePageViewsTitle
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.16 : 0.08), lineWidth: 0.8)
        }
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.006 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DiscoverStoryLinkChip: View {
    let link: WikipediaService.SearchResult
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let referenceDate: Date
    @Binding var activePageViewsTitle: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen(link, SystemBridge.isCommandPressed)
        } label: {
            Text(link.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Color.accentColor.opacity(isHovered ? 0.19 : 0.12),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(
                            Color.accentColor.opacity(isHovered ? 0.35 : 0),
                            lineWidth: 0.8
                        )
                }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.018 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                onOpen(link, false)
            } label: {
                SwiftUI.Label("Open", systemImage: "doc.text")
            }

            Button {
                onOpen(link, true)
            } label: {
                SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
            }

            Button {
                activePageViewsTitle = link.title
            } label: {
                SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
            }

            Divider()

            Button {
                _ = SystemBridge.copyText(link.title)
            } label: {
                SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
            }

            Button {
                _ = SystemBridge.copyText(
                    WikipediaURLBuilder.articleURLString(forTitle: link.title)
                )
            } label: {
                SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
            }
        }
        .popover(
            isPresented: Binding(
                get: { activePageViewsTitle == link.title },
                set: { isPresented in
                    guard !isPresented else { return }
                    if activePageViewsTitle == link.title {
                        activePageViewsTitle = nil
                    }
                }
            ),
            arrowEdge: .trailing
        ) {
            if activePageViewsTitle == link.title {
                DiscoverPageViewsPopoverContent(
                    title: link.title,
                    referenceDate: referenceDate
                )
            }
        }
    }
}

private struct DiscoverOnThisDayRow: View {
    let event: WikipediaService.DiscoverFeed.OnThisDayEvent
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let referenceDate: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPageViewsPopover = false
    @State private var isHovered = false

    var body: some View {
        Button {
            if let article = event.article {
                onOpen(article, SystemBridge.isCommandPressed)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(event.year)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(3)
                    if let article = event.article {
                        Text(article.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(event.article?.title ?? event.text)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.15 : 0.08), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.004 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let article = event.article {
                Button {
                    onOpen(article, false)
                } label: {
                    SwiftUI.Label("Open", systemImage: "doc.text")
                }

                Button {
                    onOpen(article, true)
                } label: {
                    SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
                }

                Button {
                    showingPageViewsPopover = true
                } label: {
                    SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
                }

                Divider()

                Button {
                    copyToClipboard(article.title)
                } label: {
                    SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
                }

                Button {
                    copyToClipboard(wikipediaURLString(for: article.title))
                } label: {
                    SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
                }
            }
        }
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = event.article {
                DiscoverPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
                )
            }
        }
    }

    private func copyToClipboard(_ value: String) {
        _ = SystemBridge.copyText(value)
    }

    private func wikipediaURLString(for title: String) -> String {
        WikipediaURLBuilder.articleURLString(forTitle: title)
    }
}

private struct DiscoverDidYouKnowRow: View {
    let fact: WikipediaService.DiscoverFeed.DidYouKnowFact
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let referenceDate: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPageViewsPopover = false
    @State private var isHovered = false

    var body: some View {
        Button {
            if let article = fact.article {
                onOpen(article, SystemBridge.isCommandPressed)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(fact.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(3)
                    if let article = fact.article {
                        Text(article.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(fact.article?.title ?? fact.text)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.15 : 0.08), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.004 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let article = fact.article {
                Button {
                    onOpen(article, false)
                } label: {
                    SwiftUI.Label("Open", systemImage: "doc.text")
                }

                Button {
                    onOpen(article, true)
                } label: {
                    SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
                }

                Button {
                    showingPageViewsPopover = true
                } label: {
                    SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
                }

                Divider()

                Button {
                    copyToClipboard(article.title)
                } label: {
                    SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
                }

                Button {
                    copyToClipboard(wikipediaURLString(for: article.title))
                } label: {
                    SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
                }
            }
        }
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = fact.article {
                DiscoverPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
                )
            }
        }
    }

    private func copyToClipboard(_ value: String) {
        _ = SystemBridge.copyText(value)
    }

    private func wikipediaURLString(for title: String) -> String {
        WikipediaURLBuilder.articleURLString(forTitle: title)
    }
}

private struct DiscoverHolidayRow: View {
    let holiday: WikipediaService.DiscoverFeed.HolidayItem
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let referenceDate: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPageViewsPopover = false
    @State private var isHovered = false

    var body: some View {
        Button {
            if let article = holiday.article {
                onOpen(article, SystemBridge.isCommandPressed)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(holiday.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(3)
                    if let article = holiday.article {
                        Text(article.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(holiday.article?.title ?? holiday.text)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.15 : 0.08), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.004 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let article = holiday.article {
                Button {
                    onOpen(article, false)
                } label: {
                    SwiftUI.Label("Open", systemImage: "doc.text")
                }

                Button {
                    onOpen(article, true)
                } label: {
                    SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
                }

                Button {
                    showingPageViewsPopover = true
                } label: {
                    SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
                }

                Divider()

                Button {
                    copyToClipboard(article.title)
                } label: {
                    SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
                }

                Button {
                    copyToClipboard(wikipediaURLString(for: article.title))
                } label: {
                    SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
                }
            }
        }
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = holiday.article {
                DiscoverPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
                )
            }
        }
    }

    private func copyToClipboard(_ value: String) {
        _ = SystemBridge.copyText(value)
    }

    private func wikipediaURLString(for title: String) -> String {
        WikipediaURLBuilder.articleURLString(forTitle: title)
    }
}

private struct DiscoverSearchResultRow: View {
    let result: WikipediaService.SearchResult
    let isSaved: Bool
    let onOpen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                DiscoverThumbnailSlot(
                    thumbnailURL: result.thumbnailURL,
                    size: 44,
                    cornerRadius: 8,
                    imagePadding: 3
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 14, weight: .semibold))
                    if let description = result.description {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)

                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.14 : 0), lineWidth: 0.8)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(result.title)
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.004 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}
