import SwiftUI
import SwiftData

struct TagDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tags: [Tag]
    @Binding var isPresented: Bool

    var tagToEdit: Tag?
    var onSave: ((Tag) -> Void)? = nil

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tagToEdit == nil ? "New Tag" : "Edit Tag")
                .font(.headline)

            TextField("Tag Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit {
                    save()
                }

            HStack {
                AccessibleActionButton("Cancel", keyEquivalent: "\u{1b}") {
                    isPresented = false
                }

                Spacer()

                AccessibleActionButton(
                    tagToEdit == nil ? "Create" : "Save",
                    isEnabled: !trimmedName.isEmpty,
                    keyEquivalent: "\r"
                ) {
                    save()
                }
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
        .onAppear {
            if let tag = tagToEdit {
                name = tag.name
            }
            isNameFocused = true
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }

        if let tag = tagToEdit {
            tag.name = trimmedName
            onSave?(tag)
        } else {
            let tag = Tag(name: trimmedName)
            tag.sortOrder = SortOrderAllocator.next(for: tags.map(\.sortOrder))
            modelContext.insert(tag)
            onSave?(tag)
        }
        modelContext.saveReportingFailure(operation: #function)
        isPresented = false
    }
}
