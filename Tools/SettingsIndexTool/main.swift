import Foundation
import MacWikiSettingsCatalog

struct SettingsIndexToolArguments {
    var outputURL: URL?
    var validationRootURL: URL?

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--output":
                index += 1
                guard index < arguments.count else {
                    throw SettingsIndexToolError.missingValue(argument)
                }
                outputURL = URL(fileURLWithPath: arguments[index])
            case "--validate-sources":
                index += 1
                guard index < arguments.count else {
                    throw SettingsIndexToolError.missingValue(argument)
                }
                validationRootURL = URL(fileURLWithPath: arguments[index])
            case "--help", "-h":
                throw SettingsIndexToolError.helpRequested
            default:
                throw SettingsIndexToolError.unknownArgument(argument)
            }
            index += 1
        }
    }
}

enum SettingsIndexToolError: Error, CustomStringConvertible {
    case helpRequested
    case missingValue(String)
    case unknownArgument(String)
    case uncatalogedReferences([String])

    var description: String {
        switch self {
        case .helpRequested:
            return usage
        case .missingValue(let argument):
            return "Missing value for \(argument).\n\n\(usage)"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument).\n\n\(usage)"
        case .uncatalogedReferences(let references):
            return "Uncataloged @AppStorage references:\n" + references.map { "- \($0)" }.joined(separator: "\n")
        }
    }

    private var usage: String {
        """
        Usage:
          swift run SettingsIndexTool --output <markdown-path> [--validate-sources <source-root>]

        Without --output, the generated Markdown is printed to stdout.
        """
    }
}

do {
    let parsed = try SettingsIndexToolArguments(arguments: Array(CommandLine.arguments.dropFirst()))

    if let validationRootURL = parsed.validationRootURL {
        let observed = try SettingsAppStorageReferenceScanner.references(inSourceRoot: validationRootURL)
        let missing = observed.subtracting(SettingsCatalog.catalogedAppStorageReferences).sorted()
        if !missing.isEmpty {
            throw SettingsIndexToolError.uncatalogedReferences(missing)
        }
    }

    let markdown = SettingsCatalogMarkdownRenderer.render()

    if let outputURL = parsed.outputURL {
        let outputDirectory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try markdown.write(to: outputURL, atomically: true, encoding: .utf8)
        print("Wrote \(outputURL.path)")
    } else {
        print(markdown, terminator: "")
    }
} catch let error as SettingsIndexToolError {
    switch error {
    case .helpRequested:
        print(error.description)
        exit(0)
    default:
        fputs(error.description + "\n", stderr)
        exit(1)
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
