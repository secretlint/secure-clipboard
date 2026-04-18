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
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "SecureClipboardCLI",
            path: "SecureClipboardCLI"
        ),
        .testTarget(
            name: "SecureClipboardTests",
            dependencies: ["SecureClipboard"],
            path: "SecureClipboardTests"
        )
    ]
)
