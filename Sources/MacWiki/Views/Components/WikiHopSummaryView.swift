import SwiftUI

struct WikiHopSummaryView: View {
    let session: WikiHopSession
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(spacing: 32) {
            // Icon
            Image(systemName: session.status == .completed ? "trophy.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 72))
                .foregroundStyle(session.status == .completed ? .yellow : .red)
                .shadow(color: (session.status == .completed ? Color.yellow : Color.red).opacity(0.4), radius: 20)
            
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 30, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.4))
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
}
