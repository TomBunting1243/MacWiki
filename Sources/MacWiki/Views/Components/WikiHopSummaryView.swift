import SwiftUI

struct WikiHopSummaryView: View {
    let session: WikiHopSession
    @Environment(AppState.self) private var appState
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization

    private var materialPolicy: MacWikiGlassRuntime.SurfacePolicy {
        MacWikiGlassRuntime.surfacePolicy(
            isEnabled: false,
            forceLegacyFallback: false,
            personalization: accessibilityPersonalization
        )
    }
    
    var body: some View {
        VStack(spacing: 32) {
            // Icon
            Image(systemName: session.status == .completed ? "trophy.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 72))
                .foregroundStyle(session.status == .completed ? .yellow : .red)
                .shadow(
                    color: (session.status == .completed ? Color.yellow : Color.red)
                        .opacity(materialPolicy.allowsDepth ? 0.4 : 0),
                    radius: materialPolicy.allowsDepth ? 20 : 0
                )
            
            // Title
            Text(session.status == .completed ? "Run Completed!" : "Run Failed")
                .font(.system(size: 42, weight: .bold, design: .rounded))
            
            // Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 24) {
                statItem(
                    label: "Clicks",
                    value: "\(session.clickCount)",
                    icon: "mouse.fill"
                )
                
                statItem(
                    label: "Time",
                    value: Duration.seconds((session.completedAt ?? Date()).timeIntervalSince(session.startedAt)).formatted(.time(pattern: .minuteSecond)),
                    icon: "clock.fill"
                )
                
                if let reason = session.failureReason {
                   statItem(
                       label: "Reason",
                       value: reason,
                       icon: "info.circle.fill",
                       fullWidth: true
                   )
                }
            }
            .frame(maxWidth: 300)
            
            // Start/End Info
            VStack(spacing: 12) {
                routeRow(label: "Start", title: session.startArticle.title, icon: "flag.fill")
                Image(systemName: "arrow.down")
                    .foregroundStyle(.tertiary)
                routeRow(label: "Target", title: session.targetArticle.title, icon: "flag.checkered")
            }
            .padding(20)
            .background(routeBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(
                            accessibilityPersonalization.colorSchemeContrast == .increased ? 0.34 : 0.08
                        ),
                        lineWidth: accessibilityPersonalization.colorSchemeContrast == .increased ? 1 : 0.6
                    )
            }
            
            // Actions
            HStack(spacing: 20) {
                Button {
                    appState.dismissWikiHopSession()
                } label: {
                    Text("Exit")
                        .frame(width: 100)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button {
                    // Logic to restart handled by returning to Lobby?
                    // Currently "Exit" returns to the article.
                    // To restart, we clear session, then user has to go to New Tab -> Lobby.
                    // Or we can implement a specific restart flow. 
                    // For now, simpler to just Exit.
                    appState.dismissWikiHopSession()
                    appState.showDiscoverPage() // Go to lobby
                } label: {
                    Text("Play Again")
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(48)
        .background(summaryBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(
                        accessibilityPersonalization.colorSchemeContrast == .increased ? 0.42 : 0.1
                    ),
                    lineWidth: accessibilityPersonalization.colorSchemeContrast == .increased ? 1.2 : 1
                )
        )
        .shadow(
            color: Color.black.opacity(materialPolicy.allowsDepth ? 0.2 : 0),
            radius: materialPolicy.allowsDepth ? 30 : 0,
            y: materialPolicy.allowsDepth ? 10 : 0
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            materialPolicy.usesOpaqueBackground
                ? Color(nsColor: .windowBackgroundColor)
                : Color.black.opacity(0.4)
        )
    }
    
    private func statItem(label: String, value: String, icon: String, fullWidth: Bool = false) -> some View {
        VStack(spacing: 4) {
             SwiftUI.Label(label.uppercased(), systemImage: icon)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .gridCellColumns(fullWidth ? 2 : 1)
    }
    
    private func routeRow(label: String, title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading) {
                Text(label.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Text(title)
                    .fontWeight(.medium)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var routeBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if materialPolicy.usesOpaqueBackground {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        } else {
            shape.fill(.regularMaterial)
        }
    }

    @ViewBuilder
    private var summaryBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if materialPolicy.usesOpaqueBackground {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}
