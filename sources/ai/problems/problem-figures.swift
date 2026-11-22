import FolioCore
import FolioDomain
import Foundation

extension ClaudeClient {
    // 문제집에 넣을 그림을 문제지에서 자른 그림(`crops`, PNG)을 보고 노트 그림 스타일로 다시 그린다. 문제면 같은 그림 위에 답을
    // 그린 풀이용 그림과, 풀이가 없을 때 풀이도 쓴다. `stemFigure`는 이미 다시 그린 지문의 그림이다. 풀이용 그림이 그 위에
    // 그려야 문제집과 풀이집의 그림이 같아진다. `problems`는 앞서 쓴 그림의 검사 결과이고, 있으면 고쳐 다시 쓰게 한다.
    public func drawProblemArt(
        _ job: ProblemArt.Job, crops: [Data], stemFigure: String?, previous: ProblemArtDraft? = nil, problems: [String] = []
    ) async throws -> ProblemArtDraft {
        let system: [ContentBlock] = [
            .text(
                """
                You prepare one item of a printed problem collection for a university exam. The figures cut from the scanned \
                problem sheet are blurry, so you redraw them as clean SVG in the house figure style below, and for a problem \
                you also draw its answer on the same figure.

                - "figure": one SVG that redraws every figure of this item, side by side when there are several. Keep the \
                original layout, every vertex, edge, label and number, so the statement still refers to it correctly. Add \
                detail only where the scan is hard to read, never new information. Null when the item has no figure of its \
                own (the figure of its stem is printed above it).
                - "solutionFigure": for a problem only, the same figure (its own, or the stem figure given in <stem_figure>, \
                copied exactly) with the answer drawn on top in a strong color: the matching or path as thick colored \
                edges, a coloring as filled vertices, a cut or set as a highlighted region, with short labels only. Null \
                when the answer cannot be shown on the figure.
                - "solution": only when asked for, a complete worked solution in English with the final answer, for the \
                solutions booklet. Otherwise null.

                Write all labels in English. The figure rules are written in Korean; follow them exactly. The SVG is checked \
                when it is saved: overlapping labels, labels on lines, and labels outside the viewBox are rejected.
                """, cache: true),
            .text(NoteWritingGuide.figureRules, cache: true),
            .text(MathWriting.rule, cache: true),
        ]
        var content: [ContentBlock] = []
        if !crops.isEmpty {
            content.append(.text("The figures as cut from the problem sheet:"))
            content += crops.map { .image($0, mediaType: "image/png") }
        }
        let stems = job.stems.map { "<stem number=\"\($0.number)\">\n\($0.text)\n</stem>" }.joined(separator: "\n")
        var ask = stems
        if let p = job.problem {
            ask +=
                "\n<problem number=\"\(p.number)\">\n\(p.text)\n"
                + (p.options.isEmpty ? "" : p.options.map { "- " + $0 }.joined(separator: "\n") + "\n") + "</problem>"
            if let answer = p.answer { ask += "\n<answer_key>\n\(answer)\n</answer_key>" }
            if let solution = p.solution, !job.writesSolution { ask += "\n<solution>\n\(solution)\n</solution>" }
        } else if let g = job.stem {
            ask += "\n<stem number=\"\(g.number)\">\n\(g.text)\n</stem>\nThis is a stem: draw \"figure\" only."
        }
        if let stemFigure { ask += "\n<stem_figure>\n\(stemFigure)\n</stem_figure>" }
        ask += job.draws ? "" : "\nDo not redraw the figure: set \"figure\" and \"solutionFigure\" to null."
        ask += job.writesSolution ? "\nWrite \"solution\": this problem has none on file." : "\nSet \"solution\" to null."
        content.append(.text(ask))
        var messages = [Message(role: .user, content: content)]
        if let previous, !problems.isEmpty {
            let json = (try? JSONEncoder().encode(previous)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            messages += [
                Message(role: .assistant, content: [.text(json)]),
                Message(
                    role: .user,
                    content: [.text("The figure check rejected it:\n" + problems.map { "- " + $0 }.joined(separator: "\n") + "\nFix it.")]),
            ]
        }
        return try await run(.problemArt, ProblemArtDraft.self, system: system, messages: messages)
    }
}
