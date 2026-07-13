import SwiftUI
import SwiftData
import AppKit

/// Sheet for creating or editing a label
/// Consolidates name and color management into a single interface
struct LabelDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var labels: [Label]
    @Binding var isPresented: Bool
    
    // Nil if creating, non-nil if editing
    var labelToEdit: Label?
    var onSave: ((Label) -> Void)? = nil
    
    @State private var name = ""
    @State private var selectedColor: LabelColor = .blue
    @State private var showColorPopover = false
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(labelToEdit == nil ? "New Label" : "Edit Label")
                .font(.headline)

            // Color + name row
            HStack(spacing: 12) {
                // Color picker button
                AccessibleSymbolActionButton(
                    systemImage: "circle.fill",
                    accessibilityLabel: "Choose label color",
                    accessibilityValue: selectedColor.rawValue,
                    tint: selectedColor.nativeColor,
                    pointSize: 16
                ) {
                    showColorPopover = true
                }
                .frame(width: 28, height: 28)
                .popover(isPresented: $showColorPopover, arrowEdge: .bottom) {
                    VStack(spacing: 12) {
                        Text("Select Color")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 8) {
                            ForEach(LabelColor.allCases, id: \.self) { color in
                                AccessibleSymbolActionButton(
                                    systemImage: selectedColor == color ? "checkmark.circle.fill" : "circle.fill",
                                    accessibilityLabel: color.rawValue,
                                    accessibilityValue: selectedColor == color ? "Selected" : "",
                                    tint: color.nativeColor,
                                    pointSize: 18
                                ) {
                                    selectedColor = color
                                    showColorPopover = false
                                }
                                .frame(width: 30, height: 30)
                            }
                        }
                    }
                    .padding()
                    .frame(width: 180)
                }

                // Name field
                TextField("Label Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit {
                        save()
                    }
            }

            // Standard action buttons
            HStack {
                AccessibleActionButton("Cancel", keyEquivalent: "\u{1b}") {
                    isPresented = false
                }

                Spacer()

                AccessibleActionButton(
                    labelToEdit == nil ? "Create" : "Save",
                    isEnabled: !trimmedName.isEmpty,
                    keyEquivalent: "\r"
                ) {
                    save()
                }
            }
        }
        .padding(20)
        .frame(width: 280)
        .onAppear {
            if let label = labelToEdit {
                name = label.name
                selectedColor = label.color
            }
            isNameFocused = true
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }

        if let label = labelToEdit {
            label.name = trimmedName
            label.color = selectedColor
            isPresented = false
            modelContext.saveReportingFailure(operation: #function)
            onSave?(label)
        } else {
            let label = Label(name: trimmedName, color: selectedColor)
            label.sortOrder = SortOrderAllocator.next(for: labels.map(\.sortOrder))
            modelContext.insert(label)
            isPresented = false
            modelContext.saveReportingFailure(operation: #function)
            onSave?(label)
        }
    }
}

private extension LabelColor {
    var nativeColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .gray: return .systemGray
        }
    }
}
