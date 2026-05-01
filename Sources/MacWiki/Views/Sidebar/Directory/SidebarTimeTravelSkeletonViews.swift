import SwiftUI

enum SidebarTimeTravelLoadingRowStyle {
    case feature
    case article
    case timeline
}

struct SidebarTimeTravelLoadingRow: View {
    let index: Int
    var style: SidebarTimeTravelLoadingRowStyle = .article

    private var titleMaxWidth: CGFloat {
        switch style {
        case .feature:
            return 168
        case .article:
            return 112 + CGFloat((index % 3) * 18)
        case .timeline:
            return 126 + CGFloat((index % 2) * 16)
        }
    }

    private var subtitleMaxWidth: CGFloat {
        switch style {
        case .feature:
            return 210
        case .article:
            return 154 - CGFloat((index % 3) * 12)
        case .timeline:
            return 174 - CGFloat((index % 2) * 18)
        }
    }

    private var trailingMaxWidth: CGFloat {
        26 + CGFloat((index % 3) * 9)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AppLoadingSkeletonBar(
                width: 22,
                height: 22,
                cornerRadius: 6,
                tone: .retro
            )

            VStack(alignment: .leading, spacing: 5) {
                AppLoadingSkeletonBar(
                    width: nil,
                    height: style == .feature ? 11 : 9,
                    cornerRadius: 5,
                    tone: .retro
                )
                .frame(maxWidth: titleMaxWidth, alignment: .leading)

                AppLoadingSkeletonBar(
                    width: nil,
                    height: 7.5,
                    cornerRadius: 4,
                    tone: .neutral
                )
                .frame(maxWidth: subtitleMaxWidth, alignment: .leading)

                if style == .feature {
                    AppLoadingSkeletonBar(
                        width: nil,
                        height: 7.5,
                        cornerRadius: 4,
                        tone: .neutral
                    )
                    .frame(maxWidth: 182, alignment: .leading)
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 0)

            if style == .article {
                AppLoadingSkeletonBar(
                    width: nil,
                    height: 7.5,
                    cornerRadius: 4,
                    tone: .retro
                )
                .frame(maxWidth: trailingMaxWidth, alignment: .trailing)
                .padding(.top, 6)
            }
        }
        .discoverContentRowSpacing()
        .accessibilityHidden(true)
    }
}

struct SidebarGlitchScanlineOverlay: View {
    let lineOpacity: Double

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                var y: CGFloat = 0
                while y < proxy.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    y += 3
                }
            }
            .stroke(Color.white.opacity(lineOpacity), lineWidth: 0.42)
        }
        .allowsHitTesting(false)
    }
}
