// swift-tools-version: 6.0
import PackageDescription


let package = Package(
    name: "MacWiki",
    platforms: [
        .macOS(.v15)
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
