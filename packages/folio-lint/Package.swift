// swift-tools-version: 6.2
import PackageDescription

// The code rules of AGENTS.md that a syntax tree can check (`mise run check-code`). A package of its own so the check
// builds with swift-syntax alone: inside folio-core it would wait on the Tectonic library every folio-core build needs.
let package = Package(
    name: "FolioLint",
    // Keep in sync with deploymentTarget in project.yml.
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "folio-lint", targets: ["FolioLintCommand"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "604.0.0"),
    ],
    targets: [
        .target(name: "FolioLint", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
        ], path: "sources/folio-lint"),
        .executableTarget(name: "FolioLintCommand", dependencies: ["FolioLint"], path: "sources/folio-lint-command"),
        .testTarget(name: "FolioLintTests", dependencies: ["FolioLint"], path: "tests/folio-lint-tests"),
    ]
)
