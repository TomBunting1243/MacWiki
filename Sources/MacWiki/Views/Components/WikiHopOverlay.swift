import Combine
import SwiftUI

struct WikiHopOverlay: View {
    let session: WikiHopSession
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization
    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    
    // Timer state
    @State private var timeElapsed: TimeInterval = 0
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private enum Metrics {
        static let cornerRadius: CGFloat = 18
        static let groupCornerRadius: CGFloat = 12
    }

    private var glassPolicy: MacWikiGlassRuntime.SurfacePolicy {
        MacWikiGlassRuntime.surfacePolicy(
            isEnabled: liquidGlassChrome,
            forceLegacyFallback: forceLegacyGlassFallback,
            personalization: accessibilityPersonalization
        )
    }

    private var increasedContrast: Bool {
        accessibilityPersonalization.colorSchemeContrast == .increased
    }

    var body: some View {
        HStack(spacing: 12) {
            targetGroup

            statsGroup

            giveUpButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(overlayBackground)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(
                        glassPolicy.usesOpaqueBackground
                            ? (increasedContrast ? 0.34 : 0.14)
                            : (colorScheme == .dark ? 0.075 : 0.046) + (increasedContrast ? 0.14 : 0)
                    ),
                    lineWidth: increasedContrast ? 1 : (glassPolicy.usesOpaqueBackground ? 0.6 : 0.5)
                )
        }
        .shadow(
            color: .black.opacity(
                glassPolicy.allowsDepth
                    ? (colorScheme == .dark ? 0.16 : 0.06)
                    : 0
            ),
            radius: 10,
            y: 4
        )
        .frame(width: 420)
        .onReceive(timer) { _ in
            if session.status == .active {
                timeElapsed = Date().timeIntervalSince(session.startedAt)
                
                // Auto-fail Rush mode after 5 mins (300s)
                if session.mode == .rush && timeElapsed >= 300 {
                    appState.failWikiHop(reason: "Time's up!")
                }
            }
        }
        .onAppear {
            timeElapsed = Date().timeIntervalSince(session.startedAt)
        }
    }

    private var targetGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TARGET")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            Text(session.targetArticle.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(groupBackground)
    }

    private var statsGroup: some View {
        HStack(spacing: 12) {
            SwiftUI.Label("\(session.clickCount)", systemImage: "mouse.fill")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            
            if session.mode == .rush {
                SwiftUI.Label(Duration.seconds(timeElapsed).formatted(.time(pattern: .minuteSecond)), systemImage: "timer")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(timeElapsed > 300 ? .red : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(groupBackground)
    }

    private var giveUpButton: some View {
        Button {
            appState.failWikiHop(reason: "Run abandoned")
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(buttonBackground)
        }
        .buttonStyle(.plain)
        .help("Give Up")
        .accessibilityLabel("Give Up Wiki-Hop")
    }

    @ViewBuilder
    private var overlayBackground: some View {
        let shape = Capsule(style: .continuous)
        if glassPolicy.usesOpaqueBackground {
            shape
                .fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26, *), glassPolicy.usesNativeGlass {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
                .overlay {
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.022 : 0.014))
                }
        } else {
            shape
                .fill(.thinMaterial)
                .overlay {
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.10 : 0.06))
                }
        }
    }

    private var groupBackground: some View {
        RoundedRectangle(cornerRadius: Metrics.groupCornerRadius, style: .continuous)
            .fill(
                Color(nsColor: glassPolicy.usesOpaqueBackground ? .controlBackgroundColor : .windowBackgroundColor)
                    .opacity(glassPolicy.usesOpaqueBackground ? 1 : (colorScheme == .dark ? 0.10 : 0.055))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.groupCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(increasedContrast ? 0.24 : (colorScheme == .dark ? 0.048 : 0.030)),
                        lineWidth: increasedContrast ? 1 : 0.45
                    )
            }
    }

    private var buttonBackground: some View {
        Circle()
            .fill(
                Color(nsColor: glassPolicy.usesOpaqueBackground ? .controlBackgroundColor : .windowBackgroundColor)
                    .opacity(glassPolicy.usesOpaqueBackground ? 1 : (colorScheme == .dark ? 0.10 : 0.055))
            )
            .overlay {
                Circle()
                    .strokeBorder(
                        Color.primary.opacity(increasedContrast ? 0.24 : (colorScheme == .dark ? 0.048 : 0.030)),
                        lineWidth: increasedContrast ? 1 : 0.45
                    )
            }
    }
}
