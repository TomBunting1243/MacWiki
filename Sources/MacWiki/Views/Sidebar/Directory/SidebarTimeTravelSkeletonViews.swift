import SwiftUI

struct SidebarTimeTravelSkeletonOverlay: View {
    let dateLabel: String
    let topInset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : (1.0 / 30.0))) { context in
            let progress = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.2) / 1.2
            let phase: CGFloat = reduceMotion ? -1.1 : CGFloat((progress * 2) - 1)

            VStack(alignment: .leading, spacing: 10) {
                Color.clear.frame(height: topInset + 8)

                VStack(alignment: .leading, spacing: 10) {
                    SidebarTimeTravelSkeletonHeader(
                        dateLabel: dateLabel,
                        shimmerPhase: phase,
                        shimmerEnabled: !reduceMotion
                    )

                    SidebarTimeTravelSkeletonSection(
                        titleWidth: 74,
                        rowRange: 0..<4,
                        shimmerPhase: phase,
                        shimmerEnabled: !reduceMotion
                    )

                    SidebarTimeTravelSkeletonSection(
                        titleWidth: 102,
                        rowRange: 4..<7,
                        shimmerPhase: phase,
                        shimmerEnabled: !reduceMotion
                    )
                }
                .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                LinearGradient(
                    colors: [
                        Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.07 : 0.04),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

struct SidebarTimeTravelSkeletonHeader: View {
    let dateLabel: String
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 10.5, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(nsColor: .systemPurple).opacity(0.90))
                    .frame(width: 18, height: 18)
                    .background(
                        Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.16 : 0.10),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                Text("Time Machine")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.88))

                Spacer(minLength: 0)

                Text("SCANNING")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .systemPurple).opacity(0.84))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.16 : 0.09))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(nsColor: .systemIndigo).opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 0.6)
                    )
            }

            HStack(spacing: 5) {
                SidebarTimeTravelSkeletonBar(
                    width: 22,
                    height: 22,
                    cornerRadius: 6,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled,
                    tiltDegrees: -10
                )

                SidebarTimeTravelTargetDatePill(dateLabel: dateLabel)

                SidebarTimeTravelSkeletonBar(
                    width: 22,
                    height: 22,
                    cornerRadius: 6,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled,
                    tiltDegrees: 10
                )
            }

            HStack(spacing: 6) {
                SidebarTimeTravelSkeletonChip(width: 40, shimmerPhase: shimmerPhase, shimmerEnabled: shimmerEnabled)
                SidebarTimeTravelSkeletonChip(width: 56, shimmerPhase: shimmerPhase, shimmerEnabled: shimmerEnabled)
                SidebarTimeTravelSkeletonChip(width: 44, shimmerPhase: shimmerPhase, shimmerEnabled: shimmerEnabled)

                Spacer(minLength: 0)

                SidebarTimeTravelSkeletonBar(
                    width: 22,
                    height: 22,
                    cornerRadius: 6,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled,
                    tiltDegrees: -8
                )

                SidebarTimeTravelSkeletonBar(
                    width: 22,
                    height: 22,
                    cornerRadius: 6,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled,
                    tiltDegrees: 8
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.12 : 0.07),
                            Color(nsColor: .systemIndigo).opacity(colorScheme == .dark ? 0.06 : 0.03),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 0.7)
        )
        .overlay {
            SidebarGlitchScanlineOverlay(lineOpacity: colorScheme == .dark ? 0.030 : 0.020)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .blendMode(.screen)
                .opacity(reduceMotion ? 0.08 : 0.16)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 3, y: 1)
    }
}

struct SidebarTimeTravelSkeletonSection: View {
    let titleWidth: CGFloat
    let rowRange: Range<Int>
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SidebarTimeTravelSkeletonBar(
                width: titleWidth,
                height: 8,
                cornerRadius: 4,
                shimmerPhase: shimmerPhase,
                shimmerEnabled: shimmerEnabled,
                tiltDegrees: -9
            )
            .padding(.leading, 4)
            .opacity(colorScheme == .dark ? 0.88 : 0.74)

            VStack(spacing: 4) {
                ForEach(Array(rowRange), id: \.self) { index in
                    SidebarTimeTravelSkeletonRow(
                        index: index,
                        shimmerPhase: shimmerPhase,
                        shimmerEnabled: shimmerEnabled
                    )
                }
            }
        }
    }
}

struct SidebarTimeTravelSkeletonRow: View {
    let index: Int
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var titleWidth: CGFloat {
        78 + CGFloat((index % 4) * 18)
    }

    private var subtitleWidth: CGFloat {
        126 - CGFloat((index % 3) * 14)
    }

    private var trailingWidth: CGFloat {
        28 + CGFloat((index % 3) * 10)
    }

    var body: some View {
        HStack(spacing: 8) {
            SidebarTimeTravelSkeletonBar(
                width: 22,
                height: 22,
                cornerRadius: 6,
                shimmerPhase: shimmerPhase,
                shimmerEnabled: shimmerEnabled,
                tiltDegrees: -12
            )

            VStack(alignment: .leading, spacing: 5) {
                SidebarTimeTravelSkeletonBar(
                    width: titleWidth,
                    height: 9,
                    cornerRadius: 4,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled
                )

                SidebarTimeTravelSkeletonBar(
                    width: subtitleWidth,
                    height: 7.5,
                    cornerRadius: 3.5,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled,
                    tiltDegrees: -8
                )
            }

            Spacer(minLength: 0)

            SidebarTimeTravelSkeletonBar(
                width: trailingWidth,
                height: 7.5,
                cornerRadius: 3.5,
                shimmerPhase: shimmerPhase,
                shimmerEnabled: shimmerEnabled,
                tiltDegrees: 9
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07), lineWidth: 0.6)
        )
    }
}

struct SidebarTimeTravelSkeletonChip: View {
    let width: CGFloat
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool

    var body: some View {
        SidebarTimeTravelSkeletonBar(
            width: width,
            height: 18,
            cornerRadius: 9,
            shimmerPhase: shimmerPhase,
            shimmerEnabled: shimmerEnabled,
            tiltDegrees: -7
        )
    }
}

struct SidebarTimeTravelTargetDatePill: View {
    let dateLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(dateLabel)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.84))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.14 : 0.07),
                                Color(nsColor: .systemIndigo).opacity(colorScheme == .dark ? 0.07 : 0.03),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.6)
            )
            .overlay {
                SidebarGlitchScanlineOverlay(lineOpacity: colorScheme == .dark ? 0.025 : 0.016)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .blendMode(.screen)
                    .opacity(reduceMotion ? 0.06 : 0.12)
            }
    }
}

struct SidebarTimeTravelSkeletonBar: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool
    var tiltDegrees: Double = 12

    @Environment(\.colorScheme) private var colorScheme

    private var baseGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08),
                Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.10 : 0.05),
                Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseGradient)
            .overlay {
                if shimmerEnabled {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        Color.white.opacity(colorScheme == .dark ? 0.26 : 0.48),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .rotationEffect(.degrees(tiltDegrees))
                            .offset(x: shimmerPhase * max(proxy.size.width, 1))
                    }
                    .clipped()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.10), lineWidth: 0.5)
            )
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
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
