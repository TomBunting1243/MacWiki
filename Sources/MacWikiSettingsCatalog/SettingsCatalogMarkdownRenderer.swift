import Foundation

public enum SettingsCatalogMarkdownRenderer {
    public static func render() -> String {
        var lines: [String] = [
            "---",
            "type: reference",
            "status: active",
            "generated_from: MacWikiSettingsCatalog.SettingsCatalog",
            "---",
            "# MacWiki Settings Index",
            "",
            "> [!info]",
            "> This note is generated from `MacWikiSettingsCatalog.SettingsCatalog`. When a new `@AppStorage` setting is added, add it to the catalog and run `scripts/update_settings_index.sh`.",
            "",
            "## Maintenance Contract",
            "",
            "- Source: `Sources/MacWikiSettingsCatalog/SettingsCatalog.swift`",
            "- Generator: `swift run SettingsIndexTool --output <path>`",
            "- Guardrail: `SettingsCatalogTests` scans app source for uncataloged `@AppStorage` references.",
            ""
        ]

        for section in SettingsCatalog.sections {
            lines.append("## \(section.title)")
            lines.append("")
            lines.append(section.summary)
            lines.append("")
            lines.append("| Setting | Storage key | Default | Control | Values | Visible | Notes |")
            lines.append("|---|---|---|---|---|---|---|")

            for option in section.options {
                lines.append(
                    "| \(escape(option.title)) | \(escape(option.storageKey ?? "Action")) | \(escape(option.defaultValue ?? "-")) | \(escape(option.control)) | \(escape(valuesText(for: option))) | \(option.appearsInSettings ? "Yes" : "No") | \(escape(option.summary)) |"
                )
            }

            lines.append("")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func valuesText(for option: SettingsCatalogOption) -> String {
        guard !option.values.isEmpty else { return "-" }
        return option.values.joined(separator: ", ")
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }
}
