import Foundation
import Testing

struct AppLoadingSystemTests {
    @Test func loadingPresentationUsesStaticStructureAndNativeActivity() throws {
        let loadingSource = try source("Sources/MacWiki/Views/Shared/AppLoadingSystem.swift")
        let styleSource = try source("Sources/MacWiki/Views/Shared/AppLoadingStyle.swift")

        #expect(loadingSource.contains("ProgressView()"))
        #expect(!loadingSource.contains("TimelineView"))
        #expect(!loadingSource.contains("AppLoadingBeacon"))
        #expect(!loadingSource.contains("AppLoadingScanlineOverlay"))
        #expect(!loadingSource.contains("shimmerDuration"))
        #expect(!styleSource.contains("case retro"))
        #expect(!styleSource.contains("scanlineOpacity"))
        #expect(loadingSource.contains("accessibilityLabel: \"Loading "))
        #expect(loadingSource.contains(".accessibilityHidden(true)"))
    }

    @Test func loadingChromeHonorsTransparencyAndContrastPersonalization() throws {
        let loadingSource = try source("Sources/MacWiki/Views/Shared/AppLoadingSystem.swift")

        #expect(loadingSource.contains("accessibilityPersonalization.reduceTransparency"))
        #expect(loadingSource.contains("Color(nsColor: .controlBackgroundColor)"))
        #expect(loadingSource.contains("accessibilityPersonalization.colorSchemeContrast == .increased"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
