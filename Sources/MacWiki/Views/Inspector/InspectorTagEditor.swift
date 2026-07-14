import SwiftUI

struct InspectorTagEditor: View {
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion

    @Binding var newTagName: String
    var isFieldFocused: FocusState<Bool>.Binding
    let assignedTagIDs: Set<UUID>
    let allTags: [InspectorTagSnapshot]
    let onCreateOrAssign: () -> Void
    let onAssign: (InspectorTagSnapshot) -> Void

    private var suggestedTags: [InspectorTagSnapshot] {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return allTags.filter { !assignedTagIDs.contains($0.id) }
        }
        return allTags.filter { tag in
            !assignedTagIDs.contains(tag.id) && tag.name.localizedStandardContains(trimmed)
        }
    }

    private var typedNameIsNew: Bool {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = trimmed.lowercased()
        return !allTags.contains { $0.name.lowercased() == normalized }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)

                TextField("Add or search tags", text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(MacWikiTypography.settingsHelp)
                    .focused(isFieldFocused)
                    .onSubmit {
                        onCreateOrAssign()
                    }

                if !newTagName.isEmpty {
                    Button("Clear Tag Search", systemImage: "xmark.circle.fill") {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                            newTagName = ""
                        }
                    }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .buttonStyle(.plain)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.8))
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.quaternary.opacity(0.32)))
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            }

            if typedNameIsNew {
                let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                Button(action: onCreateOrAssign) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                        Text("Create \"\(trimmed)\"")
                            .font(MacWikiTypography.compactRowMetadata)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.08), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }

            if !suggestedTags.isEmpty {
                ScrollView {
                    FlowLayout(spacing: 6) {
                        ForEach(suggestedTags) { tag in
                            Button {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                                    onAssign(tag)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 8, weight: .bold))
                                    Text(tag.name)
                                        .font(MacWikiTypography.compactRowMetadata)
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.05), in: Capsule())
                                .overlay {
                                    Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollClipDisabled()
                .frame(maxHeight: 120)
            } else if allTags.isEmpty && newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Type a name to create your first tag.")
                    .font(MacWikiTypography.settingsHelp)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}
