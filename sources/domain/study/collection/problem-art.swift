import FolioCore
import Foundation

// 문제집 PDF에 넣으려고 다시 그린 그림이다. 문제지에서 자른 그림은 흐리거나 작아서, Claude가 그것을 읽고 노트 그림 스타일(SVG)로
// 다시 그린다(`figure`). 풀이집에는 같은 그림 위에 답(매칭, 경로, 색칠)을 그린 그림(`solutionFigure`)을 둔다(#577).
// 문제나 지문 하나에 파일 하나(`.folio/problem-figures/<ID>.json`)이고, 파일이 있으면 그 항목은 다시 그리지 않는다. 그릴 것이
// 없다고 답한 항목도 빈 파일을 남겨 문제집을 만들 때마다 다시 묻지 않는다. 그림은 쓸 때 마무리한 SVG다(`NoteFigureFinish`).
public struct ProblemArt: Entity {
    // 문제나 지문의 ID다.
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID
    public var figure: String?
    public var solutionFigure: String?

    public init(id: UUID, device: DeviceID, at date: Date, figure: String? = nil, solutionFigure: String? = nil) {
        self.id = id
        createdAt = date
        updatedAt = date
        updatedBy = device
        self.figure = figure
        self.solutionFigure = solutionFigure
    }

    public static func path(_ id: UUID) -> String {
        [StandardLayout.metadataFolder, StandardLayout.problemFiguresFolder, id.uuidString + ".json"].joined(separator: "/")
    }

    // 그림 하나를 PDF 한 쪽으로 그릴 HTML이다. 쪽 크기는 viewBox의 크기(1px을 1pt로)이고, 인쇄물이라 다크 색을 쓰지 않는다.
    // viewBox가 없는 SVG는 크기를 알 수 없어 nil이다.
    public struct PrintPage: Sendable, Equatable {
        public var html: String
        public var width: Double
        public var height: Double
    }

    public static func printPage(_ svg: String) -> PrintPage? {
        guard let open = svg.range(of: "<svg"), let end = svg[open.upperBound...].firstIndex(of: ">"),
            let box = svg[open.upperBound..<end].firstMatch(of: /viewBox\s*=\s*["']([^"']*)["']/)
        else { return nil }
        let numbers = box.1.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
        let (w, h) = (numbers[2], numbers[3])
        let html =
            "<!doctype html><html><head><meta charset=\"utf-8\"><style>:root{color-scheme:light}"
            + "html,body{margin:0;background:transparent}svg{display:block;width:\(w)px;height:\(h)px}</style></head>"
            + "<body>\(svg)</body></html>"
        return PrintPage(html: html, width: w, height: h)
    }

    // 문제집을 만들 때 Claude에게 맡길 일 하나다. 지문이면 그림만, 문제면 그림, 풀이용 그림, 풀이를 맡는다.
    public struct Job: Sendable, Equatable, Identifiable {
        public var id: UUID
        public var set: UUID
        public var number: String
        public var problem: Problem?
        public var stem: ProblemGroup?
        // 문제가 딸린 지문이다. 바깥부터다. 풀이용 그림은 지문의 그림 위에 답을 그릴 수 있다.
        public var stems: [ProblemGroup]
        // 그림을 다시 그린다. 문제지 PDF가 있고 이 항목이나 그 지문에 그림이 있을 때다.
        public var draws: Bool
        // 풀이가 없는 문제라 Claude가 풀이를 쓴다.
        public var writesSolution: Bool

        public init(
            id: UUID, set: UUID, number: String, problem: Problem? = nil, stem: ProblemGroup? = nil, stems: [ProblemGroup] = [],
            draws: Bool, writesSolution: Bool
        ) {
            self.id = id
            self.set = set
            self.number = number
            self.problem = problem
            self.stem = stem
            self.stems = stems
            self.draws = draws
            self.writesSolution = writesSolution
        }

        public var figures: [ProblemRegion] { problem?.figures ?? stem?.figures ?? [] }
    }

    // 고른 문제와 그 지문 중 Claude에게 맡길 것을 문제지의 차례로 돌려준다. 지문이 먼저다. 문제의 풀이용 그림이 다시 그린 지문의
    // 그림 위에 그려야 같은 그림이 되기 때문이다. 그림은 자른 그림을 보고 그리므로 문제지 PDF가 있는 묶음(`sheets`)만 다시
    // 그리고, 이미 다시 그린 항목(`drawn`)은 다시 그리지 않는다. 풀이가 없는 문제는 그림과 상관없이 풀이를 쓴다.
    public static func jobs(sets: [ProblemSet], picked: Set<UUID>, sheets: Set<UUID>, drawn: Set<UUID>) -> [Job] {
        var stemJobs: [Job] = [], problemJobs: [Job] = []
        for set in sets {
            let tree = ProblemTree(set), sheet = sheets.contains(set.id)
            var seen: Set<UUID> = []
            for p in tree.questions where picked.contains(p.id) {
                let stems = tree.stems(of: p.id)
                for (i, g) in stems.enumerated() where !seen.contains(g.id) {
                    seen.insert(g.id)
                    guard sheet, !g.figures.isEmpty, !drawn.contains(g.id) else { continue }
                    stemJobs.append(
                        Job(
                            id: g.id, set: set.id, number: g.number, stem: g, stems: Array(stems.prefix(i)), draws: true,
                            writesSolution: false))
                }
                let pictured = sheet && (!p.figures.isEmpty || stems.contains { !$0.figures.isEmpty })
                let draws = pictured && !drawn.contains(p.id)
                let writes = (p.solution ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                guard draws || writes else { continue }
                problemJobs.append(
                    Job(id: p.id, set: set.id, number: p.number, problem: p, stems: stems, draws: draws, writesSolution: writes))
            }
        }
        return stemJobs + problemJobs
    }
}
