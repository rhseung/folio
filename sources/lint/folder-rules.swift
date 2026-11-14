import SwiftSyntax

// LocalFolders만 테스트와 미리보기와 렌더에 이 Mac의 실제 폴더를 주지 않는다. 다른 곳에서 시스템에 경로를 물으면 이
// 거절을 건너뛰므로 tests/unit/app도 검사한다. 테스트에서 손으로 만든 경로가 사용자의 끝나지 않은 녹음을 픽스처로
// 복구할 수 있기 때문이다. 패키지는 LocalFolders를 import 할 수 없으므로 어떤 사용이든 실패한다.
extension Rules {
    static var localFolders: Rule {
        Rule(
            name: "local-folders", strict: true,
            advice: "reach Application Support through LocalFolders.applicationSupport; packages don't use it"
        ) { code in
            let exempt: Set = ["sources/app/app/services/local-folders.swift", "tests/unit/app/support/local-folders-tests.swift"]
            var hits: [Hit] = []
            // folio-lint는 자기가 찾는 경로 이름을 코드에 적으므로 검사에서 뺀다.
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
