import Observation
import SwiftUI

struct DiscoverTimeMachineControlsView: View {
    let screenModel: DiscoverScreenModel
    let discoverFeedStore: DiscoverFeedStore
    let responsiveLayout: DiscoverResponsiveLayoutProfile
    var isScanning = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion

    private var prefersWideTimeMachineControls: Bool {
        responsiveLayout.prefersWideTimeMachineControls
    }

    private var showsInlineTimeMachineQuickJumps: Bool {
        responsiveLayout.showsInlineTimeMachineQuickJumps
    }

    var body: some View {
        @Bindable var screenModel = screenModel

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)

                Text("Time Machine")
                    .font(DiscoverTypography.controlLabel)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isScanning {
                    scanningBadge
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.96, anchor: .trailing))
                        )
                }

                Text(
                    isScanning
                        ? screenModel.discoverTimeMachineDateLabel
                        : (discoverFeedStore.feed?.dateLabel ?? screenModel.discoverTimeMachineDateLabel)
                )
                    .font(DiscoverTypography.editionDate)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if prefersWideTimeMachineControls {
                HStack(spacing: 6) {
                    stepButton(
                        "chevron.left",
                        accessibilityLabel: "Previous Day",
                        help: "Show the previous day"
                    ) {
                        screenModel.shiftDiscoverDate(days: -1)
                    }

                    temporalLensButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    stepButton(
                        "chevron.right",
                        accessibilityLabel: "Next Day",
                        help: "Show the next day",
                        disabled: !screenModel.canStepDiscoverDateForward
                    ) {
                        screenModel.shiftDiscoverDate(days: 1)
                    }

                    jumpMenuButton
                    refreshButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 1)

                if showsInlineTimeMachineQuickJumps {
                    quickJumpRow
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.985, anchor: .leading))
                        )
                }
            } else {
                HStack(spacing: 6) {
                    stepButton(
                        "chevron.left",
                        accessibilityLabel: "Previous Day",
                        help: "Show the previous day"
                    ) {
                        screenModel.shiftDiscoverDate(days: -1)
                    }

                    temporalLensButton
                        .layoutPriority(1)

                    stepButton(
                        "chevron.right",
                        accessibilityLabel: "Next Day",
                        help: "Show the next day",
                        disabled: !screenModel.canStepDiscoverDateForward
                    ) {
                        screenModel.shiftDiscoverDate(days: 1)
                    }
                }

                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    jumpMenuButton
                    refreshButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .discoverSurfaceChrome(
            cornerRadius: 14,
            tintColors: timeMachineTintColors,
            borderOpacity: colorScheme == .dark ? 0.42 : 0.34,
            shadowOpacity: colorScheme == .dark ? 0.16 : 0.04,
            shadowRadius: 7,
            shadowY: 2
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isScanning)
        .help("Temporal Lens: scrub day-by-day or jump to a specific date.")
    }

    private var timeMachineTintColors: [Color] {
        [
            Color.indigo.opacity(colorScheme == .dark ? 0.075 : 0.105),
            Color.accentColor.opacity(colorScheme == .dark ? 0.035 : 0.055),
            Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.018 : 0.052)
        ]
    }

    private var scanningBadge: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)

            Text("Loading")
                .font(DiscoverTypography.controlAuxiliary.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.055), in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading selected date")
    }

    @ViewBuilder
    private var quickJumpRow: some View {
        HStack(spacing: 6) {
            quickJumpButton("Today", disabled: screenModel.isDiscoverDateToday) {
                screenModel.selectedDiscoverDate = Date()
            }
            quickJumpButton("Yesterday") {
                screenModel.shiftDiscoverDate(days: -1)
            }
            quickJumpButton("7D") {
                screenModel.shiftDiscoverDate(days: -7)
            }
            quickJumpButton("30D") {
                screenModel.shiftDiscoverDate(days: -30)
            }
            quickJumpButton("1Y") {
                screenModel.shiftDiscoverDate(years: -1)
            }
            quickJumpButton("5Y") {
                screenModel.shiftDiscoverDate(years: -5)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 1)
    }

    @ViewBuilder
    private var temporalLensButton: some View {
        @Bindable var screenModel = screenModel

        Button {
            screenModel.isTimeMachineDatePickerPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 10.5, weight: .semibold))

                Text(screenModel.discoverTimeMachineDateLabel)
                    .font(DiscoverTypography.editionDate.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary.opacity(0.88))
        .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.6)
        )
        .popover(isPresented: $screenModel.isTimeMachineDatePickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker(
                    "Jump to date",
                    selection: $screenModel.selectedDiscoverDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()

                HStack(spacing: 8) {
                    Button("Today") {
                        screenModel.selectedDiscoverDate = Date()
                    }
                    .disabled(screenModel.isDiscoverDateToday)

                    Spacer(minLength: 0)

                    Button("Done") {
                        screenModel.isTimeMachineDatePickerPresented = false
                    }
                }
                .font(DiscoverTypography.controlAuxiliary.weight(.semibold))
            }
            .padding(10)
            .frame(width: 250)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if let lastX = screenModel.timeMachineLensLastDragX {
                        screenModel.stepTimeMachineLensByDrag(deltaX: value.location.x - lastX)
                    }
                    screenModel.timeMachineLensLastDragX = value.location.x
                }
                .onEnded { _ in
                    screenModel.resetTimeMachineLensDrag()
                }
        )
        .help("Drag left/right to scrub days")
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button {
            screenModel.refreshDiscover()
        } label: {
            Image(systemName: discoverFeedStore.isLoading ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary.opacity(discoverFeedStore.isLoading ? 0.38 : 0.86))
        .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.6)
        )
        .disabled(discoverFeedStore.isLoading)
        .accessibilityLabel("Refresh Discover")
        .accessibilityValue(discoverFeedStore.isLoading ? "Refreshing" : "Ready")
        .help("Refresh Discover")
    }

    @ViewBuilder
    private var jumpMenuButton: some View {
        Menu {
            Button("Today", systemImage: "sun.max") {
                screenModel.selectedDiscoverDate = Date()
            }
            .disabled(screenModel.isDiscoverDateToday)

            Button("Yesterday", systemImage: "clock.arrow.circlepath") {
                screenModel.shiftDiscoverDate(days: -1)
            }
            Button("7 days ago", systemImage: "calendar.badge.clock") {
                screenModel.shiftDiscoverDate(days: -7)
            }
            Button("30 days ago", systemImage: "calendar") {
                screenModel.shiftDiscoverDate(days: -30)
            }
            Button("1 year ago", systemImage: "clock.arrow.circlepath") {
                screenModel.shiftDiscoverDate(years: -1)
            }
            Button("5 years ago", systemImage: "clock.arrow.2.circlepath") {
                screenModel.shiftDiscoverDate(years: -5)
            }
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary.opacity(0.86))
        .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.6)
        )
        .accessibilityLabel("Jump to Date")
        .accessibilityValue(Text(screenModel.discoverTimeMachineDateLabel))
        .help("Jump to a relative date")
    }

    @ViewBuilder
    private func stepButton(
        _ symbol: String,
        accessibilityLabel: LocalizedStringKey,
        help: LocalizedStringKey,
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
        .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.6)
        )
        .accessibilityLabel(Text(accessibilityLabel))
        .help(Text(help))
    }

    @ViewBuilder
    private func quickJumpButton(
        _ title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(DiscoverTypography.controlAuxiliary.weight(.semibold))
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
}
