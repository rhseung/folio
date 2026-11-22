import FolioCore
import FolioDomain
import Foundation

extension ClaudeClient {
    // 족보와 틀린 문제를 본보기로 새 문제지를 만든다. 답과 풀이를 함께 만들어 앱이 바로 채점할 수 있게 한다.
    public func writeProblemSheet(
        units: [FolioDomain.Unit], examples: [Problem], wrong: [Problem], count: Int, context: [ContextItem], budgetTokens: Int = 60_000
    ) async throws -> ProblemSheetDraft {
        let built = ContextBuilder.build(context, budgetTokens: budgetTokens)
        func listed(_ problems: [Problem]) -> String {
            problems.map { "<problem number=\"\($0.number)\">\n\($0.text)\n</problem>" }.joined(separator: "\n")
        }
        let system =
            built.system + [
                .text(
                    """
                    You write a practice problem sheet for a university exam. Match the style, difficulty and length of the \
                    past exam problems you are given, cover the listed units in proportion, and include variations of the \
                    problems the student got wrong that test the same idea in a new setting. Number problems from 1. Write \
                    statements in the language of the examples with math in LaTeX. For every problem give the answer (for \
                    true_false, choice and short) and a complete worked solution. Set "units" to the exact unit titles. \
                    Give the sheet a short title.
                    """),
                .text(MathWriting.rule),
            ]
        let ask = ContentBlock.text(
            """
            <units>\n\(units.map { "- " + $0.title }.joined(separator: "\n"))\n</units>
            <past_problems>\n\(listed(examples))\n</past_problems>
            <wrong_problems>\n\(listed(wrong))\n</wrong_problems>
            문제 \(count)개로 된 문제지를 만들어 주세요.
            """)
        let messages = [Message(role: .user, content: built.userBlocks + [ask])]
        return try await run(.problemSheet, ProblemSheetDraft.self, system: system, messages: messages)
    }
}
