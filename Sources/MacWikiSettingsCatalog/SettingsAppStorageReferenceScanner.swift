import Foundation

public enum SettingsAppStorageReferenceScanner {
    public static func references(inSourceRoot sourceRoot: URL) throws -> Set<String> {
        let swiftFiles = try swiftFileURLs(in: sourceRoot)
        var observedReferences: Set<String> = []

        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            observedReferences.formUnion(references(inSource: source))
        }

        return observedReferences
    }

    public static func references(inSource source: String) -> Set<String> {
        let pattern = #"@AppStorage\s*\(\s*([^,\)\n]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, range: range)

        return Set(matches.compactMap { match in
            guard
                match.numberOfRanges >= 2,
                let expressionRange = Range(match.range(at: 1), in: source)
            else {
                return nil
            }

            return source[expressionRange]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        })
    }

    private static func swiftFileURLs(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true {
                urls.append(fileURL)
            }
        }
        return urls
    }
}
