// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

// Layers: CLI, Gen -> Actions -> Storage -> Domain, Actions -> Macros (compile time only), CLI -> Index -> Storage, Storage and Actions -> Markdown (note frontmatter). Domain must stay free of file I/O and UI (see AGENTS.md "레이어").
let package = Package(
    name: "FolioCore",
    // UI strings live in each target's Localizable.xcstrings as keys; the catalog generates `.key` symbols.
    defaultLocalization: "ko",
    // Keep in sync with deploymentTarget in project.yml.
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "FolioDomain", targets: ["FolioDomain"]),
        .library(name: "FolioStorage", targets: ["FolioStorage"]),
        .library(name: "FolioActions", targets: ["FolioActions"]),
        .library(name: "FolioIndex", targets: ["FolioIndex"]),
        .executable(name: "folio", targets: ["FolioCommand"]),
        .executable(name: "folio-gen", targets: ["FolioGen"]),
        .executable(name: "folio-fixture", targets: ["FolioFixtureWriter"]),
    ],
    dependencies: [
        .package(path: "../folio-markdown"),
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0"),
        // Tests only: random inputs for properties every input must keep, beside the hand-worked examples.
        .package(url: "https://github.com/x-sheep/swift-property-based", from: "1.1.2"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        // Matches the Swift 6.4 toolchain, so builds use its prebuilt copy instead of compiling swift-syntax.
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "604.0.0"),
    ],
    targets: [
        .target(name: "FolioDomain", dependencies: [.product(name: "Algorithms", package: "swift-algorithms")], path: "sources/folio-domain", resources: [.process("Localizable.xcstrings")]),
        .target(name: "FolioStorage", dependencies: ["FolioDomain", .product(name: "FolioMarkdown", package: "folio-markdown")], path: "sources/folio-storage"),
        .macro(name: "FolioMacros", dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        ], path: "sources/folio-macros"),
        .target(name: "FolioActions", dependencies: ["FolioStorage", .product(name: "FolioMarkdown", package: "folio-markdown"), "FolioMacros"], path: "sources/folio-actions", resources: [.process("Localizable.xcstrings")]),
        .target(name: "FolioIndex", dependencies: ["FolioStorage", .product(name: "FolioMarkdown", package: "folio-markdown"), .product(name: "GRDB", package: "GRDB.swift")], path: "sources/folio-index"),
        .target(name: "FolioCLI", dependencies: ["FolioActions", "FolioIndex", .product(name: "ArgumentParser", package: "swift-argument-parser"), .product(name: "GRDB", package: "GRDB.swift")], path: "sources/folio-cli", resources: [.process("Localizable.xcstrings")]),
        // Only the entry point: an executable target's test build gets no string-catalog symbols, so the commands live
        // in the FolioCLI library that the tests import.
        .executableTarget(name: "FolioCommand", dependencies: ["FolioCLI"], path: "sources/folio-command"),
        // Writes folio-cli/generated/commands.swift from the action specs. It must not need FolioCLI, so a broken
        // generated file can always be generated again.
        .executableTarget(name: "FolioGen", dependencies: ["FolioActions"], path: "sources/folio-gen"),
        // Fake GIST folders in code, for tests and for running the app or the CLI on (mise run fixture).
        .target(name: "FolioFixtures", path: "sources/folio-fixtures"),
        .executableTarget(name: "FolioFixtureWriter", dependencies: ["FolioFixtures"], path: "sources/folio-fixture-writer"),
        .testTarget(name: "FolioDomainTests", dependencies: ["FolioDomain", .product(name: "PropertyBased", package: "swift-property-based")], path: "tests/folio-domain-tests"),
        .testTarget(name: "FolioStorageTests", dependencies: ["FolioFixtures", "FolioStorage"], path: "tests/folio-storage-tests"),
        .testTarget(name: "FolioActionsTests", dependencies: ["FolioFixtures", "FolioActions"], path: "tests/folio-actions-tests"),
        .testTarget(name: "FolioIndexTests", dependencies: ["FolioFixtures", "FolioIndex", "FolioActions"], path: "tests/folio-index-tests"),
        .testTarget(name: "FolioCLITests", dependencies: ["FolioFixtures", "FolioCLI"], path: "tests/folio-cli-tests"),
        .testTarget(name: "FolioMacrosTests", dependencies: ["FolioMacros", .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")], path: "tests/folio-macros-tests"),
    ]
)
