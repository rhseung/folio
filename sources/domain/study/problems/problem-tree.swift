import Foundation

// 문제지의 나무다. 지문(`ProblemGroup`)이 폴더이고 문제가 그 안의 항목이다. 풀 문제는 `problems`의 문제뿐이고 지문은 세지
// 않는다. 형제의 순서는 그 안에서 문제지에 가장 먼저 나오는 문제(`problems`의 순서)를 따른다. 그래서 순서를 따로 적지 않아도
// 지문과 문제가 문제지의 차례대로 놓인다.
public struct ProblemTree: Sendable, Equatable {
    public enum Item: Sendable, Equatable {
        case group(ProblemGroup)
        case problem(Problem)
    }

    public struct Node: Sendable, Equatable, Identifiable {
        public var item: Item
        public var children: [Node]
        public var depth: Int

        public var id: UUID {
            switch item {
            case .group(let g): g.id
            case .problem(let p): p.id
            }
        }

        public var number: String {
            switch item {
            case .group(let g): g.number
            case .problem(let p): p.number
            }
        }

        public var group: ProblemGroup? { if case .group(let g) = item { g } else { nil } }
        public var problem: Problem? { if case .problem(let p) = item { p } else { nil } }

        // 이 마디 아래(자신 포함)의 풀 문제를 문제지 차례로 돌려준다.
        public var questions: [Problem] { (problem.map { [$0] } ?? []) + children.flatMap(\.questions) }
    }

    public var roots: [Node]

    // 상위 번호가 지문이면 그 지문 아래, 문제이면 그 문제 아래, 둘 다 아니면 맨 위에 둔다. 풀 문제가 하나도 없는 지문과,
    // 서로를 상위로 가리켜 맨 위에 닿지 않는 지문은 버린다.
    public init(problems: [Problem], groups: [ProblemGroup]) {
        let groupNumbers = Set(groups.map(\.number)), problemNumbers = Set(problems.map(\.number))
        var order: [String: Int] = [:], owner: [String: UUID] = [:]
        for (i, p) in problems.enumerated() where order[p.number] == nil {
            order[p.number] = i
            owner[p.number] = p.id
        }

        func parentKey(_ parent: String?) -> String? {
            guard let parent else { return nil }
            if groupNumbers.contains(parent) { return "g:" + parent }
            return problemNumbers.contains(parent) ? "p:" + parent : nil
        }
        var problemChildren: [String?: [Problem]] = [:], groupChildren: [String?: [ProblemGroup]] = [:]
        for p in problems { problemChildren[parentKey(p.parent == p.number ? nil : p.parent), default: []].append(p) }
        var seen: Set<String> = []
        for g in groups where seen.insert(g.number).inserted {
            groupChildren[g.parent == g.number ? nil : parentKey(g.parent), default: []].append(g)
        }

        func build(_ key: String?, depth: Int, visiting: Set<String>) -> [Node] {
            // 같은 번호의 문제가 둘이면 먼저 나온 문제만 소문제를 갖는다. 둘 다 가지면 소문제가 두 번 들어간다.
            let leaves = (problemChildren[key] ?? []).map { p in
                let below = owner[p.number] == p.id ? build("p:" + p.number, depth: depth + 1, visiting: visiting) : []
                return Node(item: .problem(p), children: below, depth: depth)
            }
            let folders = (groupChildren[key] ?? []).compactMap { g -> Node? in
                guard !visiting.contains(g.number) else { return nil }
                let node = Node(
                    item: .group(g), children: build("g:" + g.number, depth: depth + 1, visiting: visiting.union([g.number])),
                    depth: depth)
                return node.questions.isEmpty ? nil : node
            }
            func first(_ n: Node) -> Int { n.questions.compactMap { order[$0.number] }.min() ?? .max }
            return (leaves + folders).sorted { first($0) < first($1) }
        }
        // 서로를 상위로 가리키는 문제는 맨 위에서 닿지 않아 나무에 들어오지 않는다. 그런 문제도 잃지 않게 맨 위에 붙인다.
        var roots = build(nil, depth: 0, visiting: [])
        let placed = Set(roots.flatMap(\.questions).map(\.id))
        roots += problems.filter { !placed.contains($0.id) }.map { Node(item: .problem($0), children: [], depth: 0) }
        self.roots = roots
    }

    public init(_ set: ProblemSet) { self.init(problems: set.problems, groups: set.groups) }

    // 풀기 순서다. 나무를 깊이 우선으로 걸으며 풀 문제만 모은다.
    public var questions: [Problem] { roots.flatMap(\.questions) }

    // 나무에 남은 지문을 깊이 우선 차례로 돌려준다.
    public var groups: [ProblemGroup] {
        func walk(_ nodes: [Node]) -> [ProblemGroup] { nodes.flatMap { ($0.group.map { [$0] } ?? []) + walk($0.children) } }
        return walk(roots)
    }

    // 문제까지 가는 지문의 이름과 문제 번호다("Warm-up", "W1").
    public func path(to problem: UUID) -> [String] {
        func walk(_ nodes: [Node], _ trail: [String]) -> [String]? {
            for n in nodes {
                if n.problem?.id == problem { return trail + [n.number] }
                if let found = walk(n.children, trail + [n.group?.name ?? n.number]) { return found }
            }
            return nil
        }
        return walk(roots, []) ?? []
    }

    // 문제가 딸린 지문을 바깥부터 돌려준다. 풀기 화면은 이 지문의 글과 그림을 문제 위에 보인다.
    public func stems(of problem: UUID) -> [ProblemGroup] {
        func walk(_ nodes: [Node], _ trail: [ProblemGroup]) -> [ProblemGroup]? {
            for n in nodes {
                if n.problem?.id == problem { return trail }
                if let found = walk(n.children, trail + (n.group.map { [$0] } ?? [])) { return found }
            }
            return nil
        }
        return walk(roots, []) ?? []
    }
}
