// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

// Layers: CLI, Gen -> Actions -> Storage -> Domain, AI -> Domain (never writes files; results go back to the caller as
// proposals), App -> LMS -> Domain (reads the school LMS; no writes), Actions -> Macros (compile time only), CLI -> Index ->
// Storage, Storage and Actions -> Markdown (note frontmatter), and Markdown depends on no other Folio module. Domain must stay
// free of file I/O and UI (see AGENTS.md "레이어"). Lint reads the codebase and is linked into nothing else.
let package = Package(
    name: "Folio",
    // UI strings live in each target's Localizable.xcstrings as keys; the catalog generates `.key` symbols.
    defaultLocalization: "ko",
    // Keep in sync with deploymentTarget in project.yml.
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "FolioDomain", targets: ["FolioDomain"]),
        .library(name: "FolioStorage", targets: ["FolioStorage"]),
        .library(name: "FolioActions", targets: ["FolioActions"]),
        .library(name: "FolioIndex", targets: ["FolioIndex"]),
        .library(name: "FolioLMS", targets: ["FolioLMS"]),
        .library(name: "FolioMarkdown", targets: ["FolioMarkdown"]),
        .library(name: "FolioAI", targets: ["FolioAI"]),
        .executable(name: "folio", targets: ["FolioCommand"]),
        .executable(name: "folio-gen", targets: ["FolioGen"]),
        .executable(name: "folio-fixture", targets: ["FolioFixtureWriter"]),
        .executable(name: "folio-lint", targets: ["FolioLintCommand"]),
        .library(name: "FolioFixtures", targets: ["FolioFixtures"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0"),
        // Tests only: random inputs for properties every input must keep, beside the hand-worked examples.
        .package(url: "https://github.com/x-sheep/swift-property-based", from: "2.0.1"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        // GIST LMS pages (#132): students get no web service token, so Folio reads the Coursemos HTML.
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.8.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", .upToNextMinor(from: "0.9.0")),
        // Matches the Swift 6.4 toolchain, so builds use its prebuilt copy instead of compiling swift-syntax.
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "604.0.0"),
    ],
    targets: [
        .target(name: "FolioDomain", dependencies: [.product(name: "Algorithms", package: "swift-algorithms")], path: "sources/domain", resources: [.process("Localizable.xcstrings")]),
        .target(name: "FolioMarkdown", dependencies: [.product(name: "Markdown", package: "swift-markdown")], path: "sources/markdown"),
        // Tectonic, the TeX engine, as a static library for the iPad and the Mac (#41). Built in CI from sources/tectonic and
        // fetched by `mise run tectonic`, checked by sources/tectonic/pin.json; a binary target's path must be in the package.
        .binaryTarget(name: "FolioTectonic", path: "sources/tectonic/vendor/FolioTectonic.xcframework"),
        .target(name: "FolioStorage", dependencies: ["FolioDomain", "FolioTectonic", "FolioMarkdown"],
                path: "sources/storage",
                // What Tectonic links against beside itself: ICU and zlib from the SDK, CoreText for fonts, and the
                // network stack its package downloads use.
                linkerSettings: [
                    .linkedLibrary("c++"), .linkedLibrary("z"), .linkedLibrary("icucore"),
                    .linkedFramework("CoreFoundation"), .linkedFramework("CoreGraphics"), .linkedFramework("CoreText"),
                    .linkedFramework("Foundation"), .linkedFramework("Security"), .linkedFramework("SystemConfiguration"),
                    .linkedFramework("AppKit", .when(platforms: [.macOS])),
                ]),
        .target(name: "FolioAI", dependencies: ["FolioDomain"], path: "sources/ai"),
        .macro(name: "FolioMacros", dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        ], path: "sources/macros"),
        .target(name: "FolioActions", dependencies: ["FolioStorage", "FolioMarkdown", "FolioMacros"], path: "sources/actions", resources: [.process("Localizable.xcstrings")]),
        .target(name: "FolioIndex", dependencies: ["FolioStorage", "FolioMarkdown", .product(name: "GRDB", package: "GRDB.swift")], path: "sources/index"),
        .target(name: "FolioLMS", dependencies: ["FolioDomain", .product(name: "SwiftSoup", package: "SwiftSoup")], path: "sources/lms"),
        .target(name: "FolioCLI", dependencies: ["FolioActions", "FolioIndex", .product(name: "ArgumentParser", package: "swift-argument-parser"), .product(name: "GRDB", package: "GRDB.swift")], path: "sources/cli", resources: [.process("Localizable.xcstrings")]),
        // Only the entry point: an executable target's test build gets no string-catalog symbols, so the commands live
        // in the FolioCLI library that the tests import.
        .executableTarget(name: "FolioCommand", dependencies: ["FolioCLI"], path: "sources/command"),
        // Writes the action list (actions/generated) from the @Action declarations, and the CLI commands and their tree
        // (cli/generated) from the action specs and cli/commands. It must not need FolioCLI, so a broken generated file can
        // always be generated again.
        .executableTarget(name: "FolioGen", dependencies: [
            "FolioActions", .product(name: "SwiftSyntax", package: "swift-syntax"), .product(name: "SwiftParser", package: "swift-syntax"),
        ], path: "sources/gen"),
        .target(name: "FolioFixtures", dependencies: ["FolioActions"], path: "sources/fixtures"),
        .executableTarget(name: "FolioFixtureWriter", dependencies: ["FolioFixtures"], path: "sources/fixture-writer"),
        // The code rules of AGENTS.md that a syntax tree can check (`mise run check-code`). It needs swift-syntax alone, so
        // `--product folio-lint` builds without waiting on the Tectonic library every Storage build needs.
        .target(name: "FolioLint", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
        ], path: "sources/lint"),
        .executableTarget(name: "FolioLintCommand", dependencies: ["FolioLint"], path: "sources/lint-command"),
        // One test target per module, so a module's tests build only what that module needs.
        .testTarget(name: "FolioDomainTests", dependencies: ["FolioDomain", .product(name: "PropertyBased", package: "swift-property-based")], path: "tests/unit/domain"),
        .testTarget(name: "FolioMarkdownTests", dependencies: ["FolioMarkdown", .product(name: "PropertyBased", package: "swift-property-based")], path: "tests/unit/markdown"),
        .testTarget(name: "FolioStorageTests", dependencies: ["FolioFixtures", "FolioStorage"], path: "tests/unit/storage"),
        .testTarget(name: "FolioAITests", dependencies: ["FolioAI"], path: "tests/unit/ai"),
        .testTarget(name: "FolioActionsTests", dependencies: ["FolioFixtures", "FolioActions"], path: "tests/unit/actions"),
        .testTarget(name: "FolioIndexTests", dependencies: ["FolioFixtures", "FolioIndex", "FolioActions"], path: "tests/unit/index"),
        .testTarget(name: "FolioLMSTests", dependencies: ["FolioLMS"], path: "tests/unit/lms"),
        .testTarget(name: "FolioCLITests", dependencies: ["FolioFixtures", "FolioCLI"], path: "tests/unit/cli"),
        .testTarget(name: "FolioMacrosTests", dependencies: ["FolioMacros", .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")], path: "tests/unit/macros"),
        .testTarget(name: "FolioLintTests", dependencies: ["FolioLint"], path: "tests/unit/lint"),
    ]
)
