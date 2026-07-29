import CoreGraphics
import Foundation
import WebKit

@testable import MacWiki

/// A small, isolated WebKit host for reader-resource behavior tests.
///
/// Each instance owns an ephemeral website data store. Suites using the harness
/// should be both `@MainActor` and `.serialized` so WebKit process startup and
/// teardown cannot race another fixture in the same behavior family.
@MainActor
final class ReaderWebKitHarness {
    enum HarnessError: LocalizedError {
        case loadTimedOut
        case conditionTimedOut(String)
        case unexpectedResult(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .loadTimedOut:
                "Timed out loading the reader WebKit fixture"
            case .conditionTimedOut(let source):
                "Timed out waiting for reader WebKit condition: \(source)"
            case .unexpectedResult(let expected, let actual):
                "Expected WebKit result \(expected), received \(actual)"
            }
        }
    }

    let webView: WKWebView

    init(
        size: CGSize = CGSize(width: 640, height: 800),
        documentStartScripts: [String] = [],
        injectReaderStyle: Bool = true,
        injectWebViewScript: Bool = false,
        reduceTransparency: Bool = false,
        differentiateWithoutColor: Bool = false
    ) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.deterministicAnimationFrameBootstrap,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        for source in documentStartScripts {
            configuration.userContentController.addUserScript(WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        if injectReaderStyle {
            configuration.userContentController.addUserScript(WKUserScript(
                source: ReaderDocumentStyle.makeInjectionScript(
                    minimumReadableColumnWidth: 480,
                    readerTopInset: 0,
                    reduceTransparency: reduceTransparency,
                    differentiateWithoutColor: differentiateWithoutColor
                ),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }

        if injectWebViewScript {
            configuration.userContentController.addUserScript(WKUserScript(
                source: WebViewResources.scriptSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }

        webView = WKWebView(
            frame: CGRect(origin: .zero, size: size),
            configuration: configuration
        )
    }

    func loadHTML(_ html: String) async throws {
        webView.loadHTMLString(html, baseURL: nil)

        for _ in 0..<200 {
            let isReady = (try? await webView.evaluateJavaScript(
                "document.readyState === 'complete'"
            )) as? Bool == true
            if isReady, !webView.isLoading {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        throw HarnessError.loadTimedOut
    }

    func waitUntil(
        _ javaScriptCondition: String,
        attempts: Int = 100
    ) async throws {
        for _ in 0..<attempts {
            let result = try await webView.evaluateJavaScript(javaScriptCondition)
            let isSatisfied = (result as? Bool) == true
            if isSatisfied {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        throw HarnessError.conditionTimedOut(javaScriptCondition)
    }

    func evaluateBool(_ javaScript: String) async throws -> Bool {
        let result = try await webView.evaluateJavaScript(javaScript)
        if let value = result as? Bool {
            return value
        }
        if let value = result as? NSNumber {
            return value.boolValue
        }
        throw unexpectedResult(expected: "Bool", result: result)
    }

    func evaluateNumber(_ javaScript: String) async throws -> Double {
        let result = try await webView.evaluateJavaScript(javaScript)
        if let value = result as? NSNumber {
            return value.doubleValue
        }
        throw unexpectedResult(expected: "Number", result: result)
    }

    func evaluateString(_ javaScript: String) async throws -> String {
        let result = try await webView.evaluateJavaScript(javaScript)
        guard let value = result as? String else {
            throw unexpectedResult(expected: "String", result: result)
        }
        return value
    }

    func evaluateStrings(_ javaScript: String) async throws -> [String] {
        let result = try await webView.evaluateJavaScript(javaScript)
        guard let values = result as? [String] else {
            throw unexpectedResult(expected: "[String]", result: result)
        }
        return values
    }

    private func unexpectedResult(expected: String, result: Any?) -> HarnessError {
        .unexpectedResult(
            expected: expected,
            actual: result.map { String(describing: type(of: $0)) } ?? "nil"
        )
    }

    private static let deterministicAnimationFrameBootstrap = """
    window.requestAnimationFrame = function (callback) {
        return window.setTimeout(function () { callback(performance.now()); }, 0);
    };
    window.cancelAnimationFrame = function (identifier) {
        window.clearTimeout(identifier);
    };
    """
}
