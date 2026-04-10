// swift-tools-version: 6.2
import PackageDescription


let package = Package(
    name: "MacWiki",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "MacWiki", targets: ["MacWiki"])
    ],
    targets: [
        .executableTarget(
            name: "MacWiki",
            path: "Sources/MacWiki",
            exclude: [
                "Info.plist",
                "MacWiki.entitlements"
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MacWikiTests",
            dependencies: ["MacWiki"],
            path: "Tests/MacWikiTests"
        )
    ]
)
