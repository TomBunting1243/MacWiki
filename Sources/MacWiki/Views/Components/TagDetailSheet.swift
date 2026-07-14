import SwiftUI
import SwiftData

struct TagDetailSheetTarget: Equatable {
    let id: UUID
    let name: String

    init(tag: Tag) {
        id = tag.id
        name = tag.name
    }
}

struct TagDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tags: [Tag]
    @Binding var isPresented: Bool

    private let target: TagDetailSheetTarget?
    private let onSave: ((Tag) -> Void)?

    @State private var name = ""
    @State private var isUnavailable = false
    @FocusState private var isNameFocused: Bool

    init(
        isPresented: Binding<Bool>,
        tagToEdit: Tag?,
        onSave: ((Tag) -> Void)? = nil
    ) {
        _isPresented = isPresented
        target = tagToEdit.map(TagDetailSheetTarget.init)
        self.onSave = onSave
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(target == nil ? "New Tag" : "Edit Tag")
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
                    target == nil ? "Create" : "Save",
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
            if let target {
                name = target.name
            }
            isNameFocused = true
        }
        .alert("Tag No Longer Available", isPresented: $isUnavailable) {
            Button("OK") {
                isPresented = false
            }
        } message: {
            Text("The tag was removed in another window.")
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }

        let savedTag: Tag
        if let target {
            let targetID = target.id
            let descriptor = FetchDescriptor<Tag>(
                predicate: #Predicate { $0.id == targetID }
            )
            guard let tag = try? modelContext.fetch(descriptor).first else {
                isUnavailable = true
                return
            }
            tag.name = trimmedName
            savedTag = tag
        } else {
            let tag = Tag(name: trimmedName)
            tag.sortOrder = SortOrderAllocator.next(for: tags.map(\.sortOrder))
            modelContext.insert(tag)
            savedTag = tag
        }

        guard modelContext.saveReportingFailure(operation: #function) else { return }
        onSave?(savedTag)
        isPresented = false
    }
}
