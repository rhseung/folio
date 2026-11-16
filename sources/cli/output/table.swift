import FolioStorage
import Foundation

struct Table {
    var header: [String]
    var rows: [[String]] = []
    var shrink: [Int] = []

    func render() -> [String] {
        let gap = 2
        var widths = header.indices.map { i in ([header[i]] + rows.map { $0[i] }).map(\.columns).max() ?? 0 }
        if let limit = terminalWidth {
            var over = widths.reduce(0, +) + gap * (widths.count - 1) - limit
            for i in shrink where over > 0 {
                let cut = min(over, max(0, widths[i] - 4))
                widths[i] -= cut
                over -= cut
            }
        }
        func line(_ cells: [String]) -> String {
            cells.indices.map { i in
                let cell = cells[i].truncated(to: widths[i])
                return i == cells.count - 1 ? cell : cell.padded(to: widths[i])
            }.joined(separator: String(repeating: " ", count: gap))
        }
        return [line(header).styled(.dim)] + rows.map(line)
    }

    func print() { render().forEach { say($0) } }
}
