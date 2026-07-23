import SwiftUI

/// Native popover content owned by Discovery's pinned List Contents header.
struct SidebarDiscoverTimeMachineView: View {
    @Binding var selectedDate: Date
    @Binding var isHidden: Bool

    let visibleEditionDateLabel: String?
    let isLoading: Bool
    let isTimeTraveling: Bool
    let onRefresh: () -> Void

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                TimeMachineAccentMark(isActive: isBusy)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TIME MACHINE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.9)
                        .foregroundStyle(TimeMachineVisualLanguage.electricViolet)

                    Text("Browse Wikipedia editions")
                        .font(.subheadline.weight(.medium))
                }

                Spacer(minLength: 8)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading selected date")
                }
            }

            editionDatePicker

            Rectangle()
                .fill(TimeMachineVisualLanguage.accentGradient)
                .frame(height: 1)
                .opacity(0.52)

            HStack(spacing: 10) {
                editionNavigationControls

                Spacer(minLength: 8)

                jumpMenu
            }
        }
        .controlSize(.regular)
        .tint(TimeMachineVisualLanguage.electricViolet)
        .padding(14)
        .frame(width: 320)
        .timeMachineSurfaceChrome(cornerRadius: 14)
        .help("Browse Wikipedia editions from another day")
        .accessibilityValue(visibleEditionDateLabel ?? "")
    }

    private var editionDatePicker: some View {
        DatePicker(
            "Edition Date",
            selection: $selectedDate,
            in: ...Date(),
            displayedComponents: [.date]
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .accessibilityLabel("Edition Date")
    }

    private var editionNavigationControls: some View {
        ControlGroup {
            Button("Previous Day", systemImage: "chevron.left") {
                shift(days: -1)
            }
            .labelStyle(.iconOnly)
            .help("Previous Day")

            Button("Today", systemImage: "sun.max") {
                selectedDate = Date()
            }
            .disabled(isToday)

            Button("Next Day", systemImage: "chevron.right") {
                shift(days: 1)
            }
            .labelStyle(.iconOnly)
            .disabled(!canStepForward)
            .help("Next Day")
        }
        .accessibilityLabel("Edition Navigation")
    }

    private var jumpMenu: some View {
        Menu("Jump", systemImage: "calendar") {
            Button("Yesterday") { shift(days: -1) }
            Button("7 Days Ago") { shift(days: -7) }
            Button("30 Days Ago") { shift(days: -30) }
            Button("1 Year Ago") { shift(years: -1) }
            Button("5 Years Ago") { shift(years: -5) }

            Divider()

            Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                .disabled(isLoading)

            Divider()

            Button("Hide from List Contents", systemImage: "eye.slash") {
                isHidden = true
            }
        }
        .help("Jump to another edition or manage Time Machine")
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
