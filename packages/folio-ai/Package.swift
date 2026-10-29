// swift-tools-version: 6.2
import PackageDescription

// Layers: AI -> Domain. Never writes files; results go back to the caller as proposals (AGENTS.md "레이어").
let package = Package(
    name: "FolioAI",
    // Keep in sync with deploymentTarget in project.yml.
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "FolioAI", targets: ["FolioAI"]),
    ],
    dependencies: [
        .package(path: "../folio-core"),
    ],
    targets: [
        .target(name: "FolioAI", dependencies: [.product(name: "FolioDomain", package: "folio-core")], path: "sources/folio-ai"),
        .testTarget(name: "FolioAITests", dependencies: ["FolioAI"], path: "tests/folio-ai-tests"),
    ]
)
