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
            let exempt: Set = [RepoPath.localFolders, RepoPath.localFoldersTests]
            var hits: [Hit] = []
            for file in code.files(
                under: RepoPath.app, RepoPath.packages, RepoPath.tests, except: RepoPath.lint, RepoPath.lintTests, RepoPath.appE2E)
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
