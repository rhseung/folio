// swift-tools-version: 6.2
import PackageDescription

// Depends on no other Folio module (AGENTS.md "레이어").
let package = Package(
    name: "FolioMarkdown",
    // Keep in sync with deploymentTarget in project.yml.
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "FolioMarkdown", targets: ["FolioMarkdown"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", .upToNextMinor(from: "0.9.0")),
        // Random tables for the table edits' property tests (folio-core's tests use it too).
        .package(url: "https://github.com/x-sheep/swift-property-based", from: "2.0.1"),
    ],
    targets: [
        .target(name: "FolioMarkdown", dependencies: [.product(name: "Markdown", package: "swift-markdown")], path: "sources/folio-markdown"),
        .testTarget(name: "FolioMarkdownTests", dependencies: ["FolioMarkdown", .product(name: "PropertyBased", package: "swift-property-based")], path: "tests/folio-markdown-tests"),
    ]
)
