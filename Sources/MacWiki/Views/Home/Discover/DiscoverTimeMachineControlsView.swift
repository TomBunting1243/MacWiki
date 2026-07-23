import Observation
import SwiftUI

/// Native temporal navigation for the editorial Discover page.
///
/// Native DatePicker, Menu, and Button controls remain responsible for input;
/// a restrained temporal palette makes this mode distinct without replacing
/// platform control behavior.
struct DiscoverTimeMachineControlsView: View {
    let screenModel: DiscoverScreenModel
    let discoverFeedStore: DiscoverFeedStore
    let responsiveLayout: DiscoverResponsiveLayoutProfile
    var isScanning = false

    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var screenModel = screenModel

        VStack(alignment: .leading, spacing: 12) {
            header(screenModel: screenModel)

            ViewThatFits(in: .horizontal) {
                wideControls(screenModel: screenModel)
                compactControls(screenModel: screenModel)
            }
            .controlSize(.regular)
        }
        .padding(14)
        .timeMachineSurfaceChrome(cornerRadius: 14)
        .tint(TimeMachineVisualLanguage.electricViolet)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isScanning)
        .help("Browse Wikipedia editions from another day.")
    }

    private func header(screenModel: DiscoverScreenModel) -> some View {
        HStack(alignment: .center, spacing: 10) {
            TimeMachineAccentMark(isActive: isScanning)

            VStack(alignment: .leading, spacing: 2) {
                Text("TIME MACHINE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(TimeMachineVisualLanguage.electricViolet)

                Text("Browse another Wikipedia edition")
                    .font(DiscoverTypography.controlAuxiliary)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isScanning {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(TimeMachineVisualLanguage.electricViolet)
                    Text("Loading \(screenModel.discoverTimeMachineDateLabel)")
                }
                .font(DiscoverTypography.controlAuxiliary)
                .foregroundStyle(.secondary)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loading selected date")
                .accessibilityValue(screenModel.discoverTimeMachineDateLabel)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TEMPORAL EDITION")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(TimeMachineVisualLanguage.ultraviolet)
                    Text(discoverFeedStore.feed?.dateLabel ?? screenModel.discoverTimeMachineDateLabel)
                        .font(DiscoverTypography.editionDate)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func wideControls(screenModel: DiscoverScreenModel) -> some View {
        HStack(spacing: 10) {
            dateControls(screenModel: screenModel)

            Spacer(minLength: 12)

            jumpMenu(screenModel: screenModel)
            refreshButton(screenModel: screenModel)
        }
    }

    @ViewBuilder
    private func compactControls(screenModel: DiscoverScreenModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            dateControls(screenModel: screenModel)

            HStack(spacing: 8) {
                jumpMenu(screenModel: screenModel)
                refreshButton(screenModel: screenModel)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func dateControls(screenModel: DiscoverScreenModel) -> some View {
        @Bindable var screenModel = screenModel

        HStack(spacing: 6) {
            Button("Previous Day", systemImage: "chevron.left") {
                screenModel.shiftDiscoverDate(days: -1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .help("Previous Day")

            DatePicker(
                "Edition Date",
                selection: $screenModel.selectedDiscoverDate,
                in: ...Date(),
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(width: 126)
            .layoutPriority(1)
            .accessibilityLabel("Edition Date")

            Button("Next Day", systemImage: "chevron.right") {
                screenModel.shiftDiscoverDate(days: 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .disabled(!screenModel.canStepDiscoverDateForward)
            .help("Next Day")
        }
    }

    @ViewBuilder
    private func jumpMenu(screenModel: DiscoverScreenModel) -> some View {
        Menu("Jump", systemImage: "calendar.badge.clock") {
            Button("Today", systemImage: "sun.max") {
                screenModel.selectedDiscoverDate = Date()
            }
            .disabled(screenModel.isDiscoverDateToday)

            Divider()

            Button("Yesterday") {
                screenModel.shiftDiscoverDate(days: -1)
            }
            Button("7 Days Ago") {
                screenModel.shiftDiscoverDate(days: -7)
            }
            Button("30 Days Ago") {
                screenModel.shiftDiscoverDate(days: -30)
            }
            Button("1 Year Ago") {
                screenModel.shiftDiscoverDate(years: -1)
            }
            Button("5 Years Ago") {
                screenModel.shiftDiscoverDate(years: -5)
            }
        }
        .menuIndicator(.visible)
        .help("Jump to another edition")
    }

    private func refreshButton(screenModel: DiscoverScreenModel) -> some View {
        Button("Refresh", systemImage: "arrow.clockwise") {
            screenModel.refreshDiscover()
        }
        .disabled(discoverFeedStore.isLoading)
        .accessibilityLabel("Refresh Discover")
        .accessibilityValue(discoverFeedStore.isLoading ? "Refreshing" : "Ready")
        .help(discoverFeedStore.isLoading ? "Refreshing Discover…" : "Refresh Discover")
    }
}
