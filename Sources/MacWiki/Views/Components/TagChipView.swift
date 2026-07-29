import SwiftUI

struct TagChipView: View {
    @Environment(\.macWikiAccessibilityPersonalization.differentiateWithoutColor) private var differentiateWithoutColor

    let title: String
    var isSelected: Bool = false
    var isMarkedForRemoval: Bool = false
    var showsIcon: Bool = false
    var fixedWidth: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { chipContent }
                    .buttonStyle(.plain)
            } else {
                chipContent
            }
        }
    }

    private var chipColor: Color {
        if isMarkedForRemoval { return .red }
        if isSelected { return .accentColor }
        return .secondary
    }

    private var chipContent: some View {
        HStack(spacing: 4) {
            if showsIcon {
                Image(systemName: isMarkedForRemoval ? "xmark" : "number")
                    .font(.system(size: 9, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace.downUp))
            } else if isSelected && differentiateWithoutColor {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(title)
                .font(MacWikiTypography.metadataLabel)
        }
        .foregroundStyle(chipColor)
        .lineLimit(1)
        .fixedSize(horizontal: fixedWidth, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(
                    isMarkedForRemoval
                        ? Color.red.opacity(0.14)
                        : isSelected
                            ? Color.accentColor.opacity(0.14)
                            : Color.gray.opacity(0.08)
                )
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    isMarkedForRemoval
                        ? Color.red.opacity(0.3)
                        : isSelected
                            ? Color.accentColor.opacity(0.3)
                            : Color.white.opacity(0.08),
                    lineWidth: 0.8
                )
        }
        .accessibilityValue(
            isMarkedForRemoval
                ? "Marked for removal"
                : (isSelected ? "Selected" : "")
        )
    }
}
