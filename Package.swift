// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecureClipboard",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SecureClipboard",
            path: "SecureClipboard",
            exclude: [
                "cli"
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "SecureClipboardTests",
            dependencies: ["SecureClipboard"],
            path: "SecureClipboardTests"
        )
    ]
)
