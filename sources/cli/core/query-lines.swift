import FolioActions
import Foundation

// `lines:`로 선언한 읽기의 `--lines` 출력이다. 줄마다 칸을 탭으로 나눠 쓰고, 첫 칸은 다른 명령에 넘길 참조다.
protocol QueryLines: QueryOutput {
    func lines(_ result: Result, _ r: Resolver) throws -> [[String]]
}
