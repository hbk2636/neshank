// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NeshankYar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NeshankYar",
            path: "Sources/NeshankYar",
            resources: [
                // self-contained mind-map canvas (local) + Readability/Turndown for page extraction
                .copy("Resources/MindMap"),
                .copy("Resources/Extractor")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
