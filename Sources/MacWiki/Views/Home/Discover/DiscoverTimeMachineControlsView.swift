import Observation
import SwiftUI

/// Native temporal navigation for the editorial Discover page.
///
/// DatePicker, Menu, and standard bordered Button styles deliberately own
/// the control appearance. Discovery used to paint rounded rectangles around
/// borderless buttons, which became visually tiny and brittle as the reader
/// column resized.
struct DiscoverTimeMachineControlsView: View {
    let screenModel: DiscoverScreenModel
    let discoverFeedStore: DiscoverFeedStore
    let responsiveLayout: DiscoverResponsiveLayoutProfile
    var isScanning = false

    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var screenModel = screenModel

        GroupBox {
            ViewThatFits(in: .horizontal) {
                wideControls(screenModel: screenModel)
                compactControls(screenModel: screenModel)
            }
            .controlSize(.regular)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SwiftUI.Label(
                    "Time Machine",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
                .font(DiscoverTypography.controlLabel)

                Spacer(minLength: 8)

                if isScanning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading \(screenModel.discoverTimeMachineDateLabel)")
                    }
                    .font(DiscoverTypography.controlAuxiliary)
                    .foregroundStyle(.secondary)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Loading selected date")
                    .accessibilityValue(screenModel.discoverTimeMachineDateLabel)
                } else {
                    Text(discoverFeedStore.feed?.dateLabel ?? screenModel.discoverTimeMachineDateLabel)
                        .font(DiscoverTypography.editionDate)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isScanning)
        .help("Browse Wikipedia editions from another day.")
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
