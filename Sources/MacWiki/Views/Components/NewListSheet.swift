import SwiftUI
import SwiftData

/// Sheet for creating a new reading list
/// HIG-compliant: Minimal, functional, immediate response
struct NewListSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var lists: [ReadingList]
    @Binding var isPresented: Bool
    
    @State private var name = ""
    @State private var selectedIcon = "bookmark.fill"
    @State private var showIconPicker = false
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Reading List")
                .font(.headline)
            
            // Inline icon + name row
            HStack(spacing: 12) {
                // Icon selector button
                AccessibleSymbolActionButton(
                    systemImage: selectedIcon,
                    accessibilityLabel: "Choose list icon",
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
                        createList()
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
                    createList()
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
    
    private func createList() {
        guard let normalizedName = ReadingListNamePolicy.normalized(name) else { return }
        
        let list = ReadingList(name: normalizedName, icon: selectedIcon)
        list.sortOrder = SortOrderAllocator.next(for: lists.map(\.sortOrder))
        modelContext.insert(list)
        modelContext.saveReportingFailure(operation: #function)
        
        isPresented = false
    }
}
