import SwiftUI

struct WikiHopOverlay: View {
    let session: WikiHopSession
    @Environment(AppState.self) private var appState
    
    // Timer state
    @State private var timeElapsed: TimeInterval = 0
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            // Target Info
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
            
            Divider()
                .frame(height: 24)
            
            // Stats
            HStack(spacing: 12) {
                SwiftUI.Label("\(session.clickCount)", systemImage: "mouse.fill")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                
                if session.mode == .rush {
                    SwiftUI.Label(Duration.seconds(timeElapsed).formatted(.time(pattern: .minuteSecond)), systemImage: "timer")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(timeElapsed > 300 ? .red : .secondary) // 5 min limit warning
                }
            }
            
            Divider()
                .frame(height: 24)
            
            // Actions
            Button {
                appState.failWikiHop(reason: "Run abandoned")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Give Up")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 10, y: 5)
        .frame(width: 400) // Fixed width for stability
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
}
