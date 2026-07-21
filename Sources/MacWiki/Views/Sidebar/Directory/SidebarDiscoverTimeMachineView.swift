import SwiftUI

/// Compact native companion controls for Discovery's List Contents pane.
struct SidebarDiscoverTimeMachineView: View {
    @Binding var selectedDate: Date
    @Binding var isHidden: Bool

    let visibleEditionDateLabel: String?
    let isLoading: Bool
    let isTimeTraveling: Bool
    let onRefresh: () -> Void

    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion

    private var referenceDate: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }

    private var isToday: Bool {
        Calendar.current.isDate(referenceDate, inSameDayAs: Date())
    }

    private var canStepForward: Bool {
        referenceDate < Calendar.current.startOfDay(for: Date())
    }

    private var isBusy: Bool {
        isLoading || isTimeTraveling
    }

    var body: some View {
        VStack(spacing: 0) {
            if isHidden {
                HStack {
                    Button("Show Time Machine", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                            isHidden = false
                        }
                    }
                    .buttonStyle(.borderless)

                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                ViewThatFits(in: .horizontal) {
                    wideControls
                    compactControls
                }
                .controlSize(.regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()
        }
        .help("Browse Wikipedia editions from another day.")
    }

    private var wideControls: some View {
        HStack(spacing: 10) {
            timeMachineLabel

            Spacer(minLength: 8)

            dateControls
            optionsMenu
        }
    }

    private var compactControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                timeMachineLabel

                Spacer(minLength: 8)

                optionsMenu
            }

            dateControls
        }
    }

    private var timeMachineLabel: some View {
        HStack(spacing: 6) {
            SwiftUI.Label(
                "Time Machine",
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
            )
            .font(.subheadline.weight(.semibold))

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading selected date")
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityValue(visibleEditionDateLabel ?? "")
    }

    private var dateControls: some View {
        HStack(spacing: 4) {
            Button("Previous Day", systemImage: "chevron.left") {
                shift(days: -1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Previous Day")

            DatePicker(
                "Edition Date",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(width: 112)
            .layoutPriority(1)
            .accessibilityLabel("Edition Date")

            Button("Next Day", systemImage: "chevron.right") {
                shift(days: 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(!canStepForward)
            .help("Next Day")
        }
        .disabled(isBusy)
    }

    private var optionsMenu: some View {
        Menu("Time Machine Options", systemImage: "calendar.badge.clock") {
            Button("Today", systemImage: "sun.max") {
                selectedDate = Date()
            }
            .disabled(isToday)

            Divider()

            Button("Yesterday") { shift(days: -1) }
            Button("7 Days Ago") { shift(days: -7) }
            Button("30 Days Ago") { shift(days: -30) }
            Button("1 Year Ago") { shift(years: -1) }
            Button("5 Years Ago") { shift(years: -5) }

            Divider()

            Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                .disabled(isLoading)

            Button("Hide Time Machine", systemImage: "eye.slash") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    isHidden = true
                }
            }
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .help("Jump to another edition")
        .accessibilityLabel("Time Machine options")
    }

    private func shift(days: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let shifted = calendar.date(byAdding: .day, value: days, to: referenceDate) ?? referenceDate
        selectedDate = min(shifted, today)
    }

    private func shift(years: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let shifted = calendar.date(byAdding: .year, value: years, to: referenceDate) ?? referenceDate
        selectedDate = min(shifted, today)
    }
}
