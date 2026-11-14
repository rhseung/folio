import FolioDomain
import Foundation

// 읽기 선언이다. 액션처럼 한 번 선언하면 CLI 명령(`folio-gen`), `--json` 출력, MCP 도구가 같은 선언을 읽는다. 결과 값을
// 그대로 JSON으로 쓰고, 사람용 출력은 CLI가 결과 값마다 하나씩 그린다.
public protocol Query: Codable, Sendable {
    associatedtype Result: Encodable
    static var spec: QuerySpec { get }
    func read(_ ctx: ReadContext) throws -> Result
}

extension Query {
    public static var command: String { spec.command }
}
