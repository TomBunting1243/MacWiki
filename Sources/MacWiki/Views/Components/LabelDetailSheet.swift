import SwiftUI
import SwiftData

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
                Button {
                    showColorPopover = true
                } label: {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(selectedColor.swiftUIColor)
                        .frame(width: 24, height: 24)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose label color")
                .accessibilityValue(selectedColor.rawValue)
                .popover(isPresented: $showColorPopover, arrowEdge: .bottom) {
                    VStack(spacing: 12) {
                        Text("Select Color")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 8) {
                            ForEach(LabelColor.allCases, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                    showColorPopover = false
                                } label: {
                                    Circle()
                                        .fill(color.swiftUIColor)
                                        .frame(width: 24, height: 24)
                                        .overlay {
                                            if selectedColor == color {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .shadow(radius: 1)
                                            }
                                        }
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help(color.rawValue)
                                .accessibilityLabel(color.rawValue)
                                .accessibilityValue(selectedColor == color ? "Selected" : "")
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
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(labelToEdit == nil ? "Create" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
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
