import SwiftUI

struct WikiHopLobbyView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedMode: WikiHopSession.Mode = .chill
    @State private var isLoading = false
    @State private var error: String?
    
    private let service = WikipediaService.shared

    var body: some View {
        VStack(spacing: 40) {
            headerSection
            
            modeSection
            
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button {
                startNewGame()
            } label: {
                if isLoading {
                    HStack(spacing: 8) {
                        AppLoadingActivityMark(tone: .accent)
                        Text("Starting")
                    }
                    .frame(width: 100)
                } else {
                    Text("Start Run")
                        .frame(width: 100)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)
            .keyboardShortcut(.defaultAction)
            
            howToPlaySection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                
                // Subtle background decoration
                Circle()
                    .fill(Color.accentColor.opacity(0.05))
                    .frame(width: 600, height: 600)
                    .offset(y: -200)
                    .blur(radius: 100)
            }
            .ignoresSafeArea()
        )
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(
                    colors: [.accentColor, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: .accentColor.opacity(0.3), radius: 10, y: 5)
            
            Text("Wiki-Hop")
                .font(.system(size: 42, weight: .bold, design: .rounded))
            
            Text("Navigate from point A to point B\nusing only links.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var modeSection: some View {
        Picker("Mode", selection: $selectedMode) {
            Text("Chill").tag(WikiHopSession.Mode.chill)
            Text("Rush").tag(WikiHopSession.Mode.rush)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .labelsHidden()
    }
    
    private var howToPlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rules")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            validityRow(icon: "checkmark", text: "Click links in the article body")
            validityRow(icon: "xmark", text: "No search or sidebar navigation")
            validityRow(icon: "xmark", text: "No external tools")
            
            if selectedMode == .rush {
                validityRow(icon: "timer", text: "Time attack: 5 minutes limit")
            } else {
                validityRow(icon: "hare", text: "Take your time, find the shortest path")
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: 340)
    }
    
    private func validityRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(icon == "checkmark" ? .green : (icon == "timer" || icon == "hare" ? .secondary : .red))
                .frame(width: 20)
             Text(text)
                .font(.subheadline)
        }
    }
    
    private func startNewGame() {
        isLoading = true
        error = nil
        
        Task {
            do {
                // Fetch 2 random articles
                let articles = try await service.fetchRandomArticles(count: 2)
                guard articles.count == 2 else {
                    throw WikipediaService.WikipediaError.noResults
                }
                
                let start = Article(
                    id: articles[0].id,
                    title: articles[0].title,
                    description: articles[0].description,
                    thumbnailURL: articles[0].thumbnailURL
                )
                
                let target = Article(
                    id: articles[1].id,
                    title: articles[1].title,
                    description: articles[1].description,
                    thumbnailURL: articles[1].thumbnailURL
                )
                
                await MainActor.run {
                    appState.startWikiHop(mode: selectedMode, start: start, target: target)
                    appState.openArticle(start, inNewTab: false) // Navigate current tab to start
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to start game: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}
