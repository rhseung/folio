import Foundation

struct Fence {
    let char: Character
    let count: Int
    let info: String

    init?(_ line: String) {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = line.dropFirst(indent)
        guard let first = rest.first, first == "`" || first == "~" else { return nil }
        let run = rest.prefix { $0 == first }.count
        guard run >= 3 else { return nil }
        let info = rest.dropFirst(run).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        char = first
        count = run
        self.info = info
    }

    func closes(_ open: Fence) -> Bool {
        char == open.char && count >= open.count && info.isEmpty
    }
}
