import SwiftUI
import SwiftData

/// Sheet for creating a new area/folder
struct NewAreaSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var areas: [Area]
    @Binding var isPresented: Bool
    
    @State private var name = ""
    @State private var selectedIcon = "folder.fill"
    @State private var showIconPicker = false
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Folder")
                .font(.headline)
            
            // Inline icon + name row
            HStack(spacing: 12) {
                // Icon selector button
                AccessibleSymbolActionButton(
                    systemImage: selectedIcon,
                    accessibilityLabel: "Choose folder icon",
                    accessibilityValue: selectedIcon
                ) {
                    showIconPicker = true
                }
                .frame(width: 36, height: 36)
                
                // Name field
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit {
                        createArea()
                    }
            }
            
            // Standard action buttons
            HStack {
                AccessibleActionButton("Cancel", keyEquivalent: "\u{1b}") {
                    isPresented = false
                }
                
                Spacer()
                
                AccessibleActionButton(
                    "Create",
                    isEnabled: !trimmedName.isEmpty,
                    keyEquivalent: "\r"
                ) {
                    createArea()
                }
            }
        }
        .padding(20)
        .frame(width: 280)
        .onAppear {
            isNameFocused = true
        }
        .sheet(isPresented: $showIconPicker) {
            SFSymbolPicker(selectedSymbol: $selectedIcon)
        }
    }
    
    private func createArea() {
        guard !trimmedName.isEmpty else { return }
        
        let area = Area(name: trimmedName, icon: selectedIcon)
        area.sortOrder = SortOrderAllocator.next(for: areas.map(\.sortOrder))
        modelContext.insert(area)
        modelContext.saveReportingFailure(operation: #function)
        
        isPresented = false
    }
}
