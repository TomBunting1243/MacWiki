import SwiftUI

struct ReferenceRowView: View {
    let item: ArticleReferenceItem
    let displayLabel: String
    let isSelected: Bool
    let isFocused: Bool
    let hasLink: Bool
    let onToggleSelection: () -> Void
    let onOpen: () -> Void
    let onCopy: (ReferenceExportFormat) -> Void
    let onFocus: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var focusPulse = false
    @State private var pulseResetWorkItem: DispatchWorkItem?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                labelRow

                Text(item.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .lineSpacing(2)

                actionRow
            }
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
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus()
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onChange(of: isFocused) { _, newValue in
            if newValue {
                triggerFocusPulse()
            } else {
                pulseResetWorkItem?.cancel()
                focusPulse = false
            }
        }
        .onDisappear {
            pulseResetWorkItem?.cancel()
            pulseResetWorkItem = nil
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

            if hasLink {
                Divider()

                Button {
                    onOpen()
                } label: {
                    SwiftUI.Label("Open Source", systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    private var labelRow: some View {
        HStack(spacing: 6) {
            Text("[\(displayLabel)]")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12), in: Capsule())

            if let group = item.group, !group.isEmpty {
                Text(group)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                onOpen()
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hasLink ? .secondary : .tertiary)
                    .frame(width: 22, height: 22)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!hasLink)
            .help(hasLink ? "Open source" : "No link available")

            Button {
                onCopy(.plainText)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    }
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
        pulseResetWorkItem?.cancel()
        focusPulse = false
        withAnimation(.easeOut(duration: 0.12)) {
            focusPulse = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) {
                focusPulse = false
            }
        }
        pulseResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: workItem)
    }
}
