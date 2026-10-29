// swift-tools-version: 6.2
import PackageDescription

// Depends on no other Folio module (CLAUDE.md "레이어").
let package = Package(
    name: "FolioMarkdown",
    // Keep in sync with deploymentTarget in project.yml.
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "FolioMarkdown", targets: ["FolioMarkdown"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", .upToNextMinor(from: "0.9.0")),
    ],
    targets: [
        .target(name: "FolioMarkdown", dependencies: [.product(name: "Markdown", package: "swift-markdown")], path: "sources/folio-markdown"),
        .testTarget(name: "FolioMarkdownTests", dependencies: ["FolioMarkdown"], path: "tests/folio-markdown-tests"),
    ]
)
