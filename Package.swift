// swift-tools-version: 6.2
import PackageDescription


let package = Package(
    name: "MacWiki",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "MacWiki", targets: ["MacWiki"]),
        .executable(name: "SettingsIndexTool", targets: ["SettingsIndexTool"]),
        .library(name: "MacWikiSettingsCatalog", targets: ["MacWikiSettingsCatalog"])
    ],
    targets: [
        .target(
            name: "MacWikiSettingsCatalog",
            path: "Sources/MacWikiSettingsCatalog"
        ),
        .executableTarget(
            name: "MacWiki",
            dependencies: ["MacWikiSettingsCatalog"],
            path: "Sources/MacWiki",
            exclude: [
                "Info.plist",
                "MacWiki.entitlements"
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "SettingsIndexTool",
            dependencies: ["MacWikiSettingsCatalog"],
            path: "Tools/SettingsIndexTool"
        ),
        .testTarget(
            name: "MacWikiTests",
            dependencies: ["MacWiki", "MacWikiSettingsCatalog"],
            path: "Tests/MacWikiTests"
        )
    ]
)
