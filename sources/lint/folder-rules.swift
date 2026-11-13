import SwiftSyntax

// The app reaches Application Support only through LocalFolders, which refuses this Mac's real folders to tests,
// previews and renders. A path asked of the system anywhere else would skip that refusal; tests/unit/app is checked too,
// since a test is where a hand-made path would recover the user's unfinished recordings into a fixture. Packages
// can't import LocalFolders and have no business there, so for them any use fails.
extension Rules {
    static var localFolders: Rule {
        Rule(
            name: "local-folders", strict: true,
            advice: "reach Application Support through LocalFolders.applicationSupport; packages don't use it"
        ) { code in
            let exempt: Set = ["sources/app/app/services/local-folders.swift", "tests/unit/app/support/local-folders-tests.swift"]
            var hits: [Hit] = []
            // folio-lint names the paths it looks for.
            for file in code.files(
                under: "sources", "tests", except: "sources/lint", "sources/lint-command", "tests/unit/lint", "tests/e2e/app")
            where !exempt.contains(file.path) {
                for token in file.tokens {
                    switch token.tokenKind {
                    case .identifier(let name) where systemFolderCalls.contains(name):
                        hits.append(Hit("local-folders", file, file.line(of: token), name))
                    case .stringSegment(let text) where text.contains("Library/Application Support"):
                        hits.append(Hit("local-folders", file, file.line(of: token), "\"Library/Application Support\""))
                    default:
                        break
                    }
                }
            }
            return hits
        }
    }

    static let systemFolderCalls: Set = ["applicationSupportDirectory", "NSSearchPathForDirectoriesInDomains"]
}
