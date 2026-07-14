import SwiftUI

struct ReferenceRowView: View {
    let item: ArticleReferenceItem
    let displayLabel: String
    let isSelected: Bool
    let isFocused: Bool
    let hasOpenTarget: Bool
    let onToggleSelection: () -> Void
    let onOpen: () -> Void
    let onCopy: (ReferenceExportFormat) -> Void
    let onFocus: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var focusPulse = false
    @State private var pulseResetTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(
                isSelected ? "Deselect Reference" : "Select Reference",
                systemImage: isSelected ? "checkmark.circle.fill" : "circle",
                action: onToggleSelection
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    onFocus()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.84)) {
                        isExpanded.toggle()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        labelRow

                        Text(item.text)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(isExpanded ? nil : 4)
                            .lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Collapse this reference" : "Expand this reference")

                actionRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(rowBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)

            if isFocused {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.2)
            }

            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.6)
                .opacity(focusPulse ? 1 : 0)
                .scaleEffect(focusPulse ? 1.02 : 0.98)
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onChange(of: isFocused) { _, newValue in
            if newValue {
                withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.84)) {
                    isExpanded = true
                }
                triggerFocusPulse()
            } else {
                pulseResetTask?.cancel()
                focusPulse = false
            }
        }
        .onDisappear {
            pulseResetTask?.cancel()
            pulseResetTask = nil
        }
        .contextMenu {
            Button {
                onCopy(.plainText)
            } label: {
                SwiftUI.Label("Copy as Plain Text", systemImage: "doc.on.doc")
            }

            Button {
                onCopy(.markdown)
            } label: {
                SwiftUI.Label("Copy as Markdown", systemImage: "doc.text")
            }

            Button {
                onCopy(.html)
            } label: {
                SwiftUI.Label("Copy as HTML", systemImage: "chevron.left.slash.chevron.right")
            }

            Divider()

            Button {
                onToggleSelection()
            } label: {
                SwiftUI.Label(isSelected ? "Deselect" : "Select", systemImage: isSelected ? "minus.circle" : "checkmark.circle")
            }

            if hasOpenTarget {
                Divider()

                Button {
                    onOpen()
                } label: {
                    SwiftUI.Label("Open Source", systemImage: "safari")
                }
            }
        }
    }

    private var labelRow: some View {
        HStack(spacing: 6) {
            Text("[\(displayLabel)]")
                .font(MacWikiTypography.referenceBadge)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12), in: Capsule())

            if let group = item.group, !group.isEmpty {
                Text(group)
                    .font(MacWikiTypography.referenceBadge)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Open Source", systemImage: "safari", action: onOpen)
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(hasOpenTarget ? .secondary : .tertiary)
            .frame(width: 22, height: 22)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            }
            .buttonStyle(.plain)
            .disabled(!hasOpenTarget)
            .help(hasOpenTarget ? "Open source or search by title" : "No source text available")

            Button("Copy Reference", systemImage: "doc.on.clipboard") {
                onCopy(.plainText)
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    private var rowBackground: Color {
        if isFocused {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.2 : 0.12)
        }
        return Color.gray.opacity(isHovered ? 0.08 : 0.035)
    }

    private func triggerFocusPulse() {
        pulseResetTask?.cancel()
        focusPulse = false
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            focusPulse = true
        }

        pulseResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                focusPulse = false
            }
        }
    }
}
