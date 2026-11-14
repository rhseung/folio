import FolioActions
import FolioDomain
import Foundation

// 읽기 선언의 사람용 출력이다. 생성한 명령이 이것을 부르므로, 읽기 선언마다 하나가 있어야 컴파일된다. `--json`은 결과
// 값을 그대로 쓴다.
protocol QueryOutput: Query {
    func say(_ result: Result, _ r: Resolver) throws
}

func show<Q: QueryOutput>(_ query: Q, _ g: GlobalOptions, ctx: ActionContext) throws {
    let result = try read(query, ctx)
    if g.json { return try printJSON(result) }
    try query.say(result, Resolver(ctx))
}

func show<Q: QueryLines>(_ query: Q, _ g: GlobalOptions, lines: Bool, ctx: ActionContext) throws {
    guard lines, !g.json else { return try show(query, g, ctx: ctx) }
    for cells in try query.lines(try read(query, ctx), Resolver(ctx)) { line(cells) }
}

private func read<Q: Query>(_ query: Q, _ ctx: ActionContext) throws -> Q.Result {
    if Q.spec.grades { try GradesLock.require(minutes: try ctx.settings().gradesUnlockMinutes) }
    return try reporting { try query.read(ReadContext(ctx)) }
}
