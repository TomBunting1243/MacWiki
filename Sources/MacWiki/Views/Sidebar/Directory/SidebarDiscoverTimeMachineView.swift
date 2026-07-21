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
        VStack(alignment: .leading, spacing: 14) {
            popoverHeader
            editionDatePicker
            editionNavigationControls
            jumpAndRefreshControls

            Button("Hide from List Contents", systemImage: "eye.slash") {
                isHidden = true
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("You can show Time Machine again in Settings")
        }
        .controlSize(.regular)
        .padding(16)
        .frame(width: 286)
        .help("Browse Wikipedia editions from another day")
    }

    private var popoverHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                SwiftUI.Label(
                    "Time Machine",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
                .font(.headline)

                Spacer(minLength: 8)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading selected date")
                }
            }

            Text(visibleEditionDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(visibleEditionDateLabel ?? "")
    }

    private var visibleEditionDescription: String {
        if let visibleEditionDateLabel {
            return isTimeTraveling
                ? "Showing \(visibleEditionDateLabel) while the selected edition loads."
                : "Showing the \(visibleEditionDateLabel) edition."
        }
        return "Choose a day to browse Wikipedia's edition for that date."
    }

    private var editionDatePicker: some View {
        DatePicker(
            "Edition",
            selection: $selectedDate,
            in: ...Date(),
            displayedComponents: [.date]
        )
        .datePickerStyle(.field)
        .disabled(isBusy)
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
        .disabled(isBusy)
        .accessibilityLabel("Edition Navigation")
    }

    private var jumpAndRefreshControls: some View {
        HStack(spacing: 10) {
            Menu("Jump", systemImage: "calendar.badge.clock") {
                Button("Yesterday") { shift(days: -1) }
                Button("7 Days Ago") { shift(days: -7) }
                Button("30 Days Ago") { shift(days: -30) }
                Button("1 Year Ago") { shift(years: -1) }
                Button("5 Years Ago") { shift(years: -5) }
            }

            Spacer(minLength: 8)

            Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                .disabled(isLoading)
        }
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
