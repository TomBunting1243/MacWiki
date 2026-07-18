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

    var body: some View {
        if isHidden {
            HStack(spacing: 8) {
                SwiftUI.Label("Time Machine Hidden", systemImage: "clock.badge.xmark")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button("Show") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        isHidden = false
                    }
                }
            }
            .font(.caption)
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
        } else {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Button("Previous Day", systemImage: "chevron.left") {
                            shift(days: -1)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
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
                        .buttonStyle(.bordered)
                        .disabled(!canStepForward)
                        .help("Next Day")
                    }

                    HStack(spacing: 8) {
                        if isLoading || isTimeTraveling {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Loading selected date")
                        }

                        jumpMenu

                        Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                            .labelStyle(.iconOnly)
                            .disabled(isLoading)
                            .accessibilityLabel("Refresh Discover")
                            .accessibilityValue(isLoading ? "Refreshing" : "Ready")
                            .help("Refresh Discover")

                        Spacer(minLength: 0)
                    }
                }
                .controlSize(.small)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SwiftUI.Label(
                        "Time Machine",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                    )

                    Spacer(minLength: 6)

                    if let visibleEditionDateLabel,
                       !visibleEditionDateLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(visibleEditionDateLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
            }
            .help("Browse Wikipedia editions from another day.")
        }
    }

    private var jumpMenu: some View {
        Menu("Jump", systemImage: "calendar.badge.clock") {
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

            Button("Hide Time Machine", systemImage: "eye.slash") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    isHidden = true
                }
            }
        }
        .menuIndicator(.visible)
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
