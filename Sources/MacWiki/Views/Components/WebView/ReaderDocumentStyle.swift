import CoreGraphics
import Foundation
import OSLog

enum ReaderDocumentStyle {
    static let minimumReadableWidthPlaceholder = "__MACWIKI_MINIMUM_READABLE_COLUMN_WIDTH_PX__"
    static let readerTopInsetPlaceholder = "__MACWIKI_READER_TOP_INSET_PX__"

    static let cssTemplate = WebViewResourceLoader.source(
        named: "Reader",
        withExtension: "css"
    )

    static let tableEnhancementScript = WebViewResourceLoader.source(
        named: "ReaderTableEnhancements",
        withExtension: "js"
    )

    static func renderedCSS(
        source: String = cssTemplate,
        minimumReadableColumnWidth: CGFloat,
        readerTopInset: CGFloat
    ) -> String {
        source
            .replacingOccurrences(
                of: minimumReadableWidthPlaceholder,
                with: roundedPixelValue(minimumReadableColumnWidth)
            )
            .replacingOccurrences(
                of: readerTopInsetPlaceholder,
                with: roundedPixelValue(readerTopInset)
            )
    }

    static func makeInjectionScript(
        css: String,
        tableEnhancementScript: String = tableEnhancementScript,
        reduceTransparency: Bool = false
    ) -> String {
        let cssLiteral = WebViewJavaScript.stringLiteral(css)

        return """
        (function() {
            function appendToDocumentHead(node) {
                if (document.head) {
                    document.head.appendChild(node);
                } else if (document.documentElement) {
                    document.documentElement.appendChild(node);
                }
            }

            \(ReaderDocumentAccessibilityStyle.updateScript(
                reduceTransparency: reduceTransparency
            ))

            var style = document.createElement('style');
            style.textContent = \(cssLiteral);
            appendToDocumentHead(style);

            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1';
            appendToDocumentHead(meta);

            \(tableEnhancementScript)
        })();
        """
    }

    static func makeInjectionScript(
        minimumReadableColumnWidth: CGFloat,
        readerTopInset: CGFloat,
        reduceTransparency: Bool = false
    ) -> String {
        makeInjectionScript(
            css: renderedCSS(
                minimumReadableColumnWidth: minimumReadableColumnWidth,
                readerTopInset: readerTopInset
            ),
            reduceTransparency: reduceTransparency
        )
    }

    private static func roundedPixelValue(_ value: CGFloat) -> String {
        guard value.isFinite else { return "0" }
        return String(Int(max(0, value).rounded()))
    }
}

enum WebViewJavaScript {
    static func stringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              var literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }

        // JavaScriptCore accepts these characters in modern source text, but
        // escaping them keeps the literal valid across every supported WebKit.
        literal = literal
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return literal
    }
}

enum WebViewResourceLoader {
    private static let logger = Logger(subsystem: "MacWiki", category: "WebViewResources")

    static func source(named name: String, withExtension fileExtension: String) -> String {
        guard let url = resolvedURL(named: name, withExtension: fileExtension),
              let data = try? Data(contentsOf: url),
              let source = String(data: data, encoding: .utf8) else {
            logger.fault("Missing required web resource: \(name, privacy: .public).\(fileExtension, privacy: .public)")
            assertionFailure("Missing \(name).\(fileExtension) in app resources")
            return ""
        }
        return source
    }

    static func resolvedURL(
        named name: String,
        withExtension fileExtension: String,
        mainBundle: Bundle = .main,
        moduleBundle: Bundle = .module
    ) -> URL? {
        if let directURL = mainBundle.url(forResource: name, withExtension: fileExtension) {
            return directURL
        }

        if let resourceURL = mainBundle.resourceURL,
           let packagedResourceBundle = Bundle(
               url: resourceURL.appending(path: "MacWiki_MacWiki.bundle", directoryHint: .isDirectory)
           ),
           let packagedURL = packagedResourceBundle.url(
               forResource: name,
               withExtension: fileExtension
           ) {
            return packagedURL
        }

        if let legacyNestedURL = mainBundle.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "MacWiki_MacWiki.bundle"
        ) {
            return legacyNestedURL
        }

        return moduleBundle.url(forResource: name, withExtension: fileExtension)
    }
}

enum WebViewResources {
    static let scriptSource = WebViewResourceLoader.source(
        named: "WebView",
        withExtension: "js"
    )
}
