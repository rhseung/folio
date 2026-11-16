import Foundation

public enum TextDiff {
    public enum Line: Hashable, Sendable {
        case same(String)
        case removed(String)
        case added(String)
        case skipped(Int)
    }

    public static func lines(from old: String, to new: String, context: Int = 2) -> [Line] {
        fold(full(from: split(old), to: split(new)), context: context)
    }

    public static func full(from old: [String], to new: [String]) -> [Line] {
        let difference = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var out: [Line] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) {
                out.append(.removed(old[i]))
                i += 1
            } else if j < new.count, inserted.contains(j) {
                out.append(.added(new[j]))
                j += 1
            } else {
                out.append(.same(old[i]))
                i += 1
                j += 1
            }
        }
        return out
    }

    // "1 line skipped" 표시도 한 줄을 차지하므로, 두 줄 이상을 숨길 때만 접는다.
    public static func fold(_ lines: [Line], context: Int) -> [Line] {
        guard lines.contains(where: { if case .same = $0 { false } else { true } }) else { return [] }
        var out: [Line] = []
        var run: [Line] = []
        func flush(leading: Bool, trailing: Bool) {
            let keepHead = leading ? 0 : context, keepTail = trailing ? 0 : context
            if run.count - keepHead - keepTail >= 2 {
                out += run.prefix(keepHead)
                out.append(.skipped(run.count - keepHead - keepTail))
                out += run.suffix(keepTail)
            } else {
                out += run
            }
            run = []
        }

        for line in lines {
            if case .same = line {
                run.append(line)
            } else {
                flush(leading: out.isEmpty, trailing: false)
                out.append(line)
            }
        }
        flush(leading: false, trailing: true)
        return out
    }

    // 마지막 줄 끝의 줄바꿈은 새 줄을 시작하지 않는다.
    public static func split(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }
}
