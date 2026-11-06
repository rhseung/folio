import Foundation

/// What a rewrite of a text file changes, line by line, as the user sees it before approving the rewrite. Long
/// unchanged runs fold into a count so a two-line change isn't lost in the rest of the note.
public enum TextDiff {
    public enum Line: Hashable, Sendable {
        case same(String)
        case removed(String)
        case added(String)
        /// Unchanged lines left out.
        case skipped(Int)
    }

    /// Empty when nothing changes. `context` unchanged lines stay on each side of a change.
    public static func lines(from old: String, to new: String, context: Int = 2) -> [Line] {
        fold(full(from: split(old), to: split(new)), context: context)
    }

    /// Every line of both texts: `same` and `removed` read in order give the old text, `same` and `added` the new one.
    /// Removals come before the additions that replace them, as a reader expects old before new.
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
                // Neither side changes here, so both point at the same line of the common subsequence.
                out.append(.same(old[i]))
                i += 1
                j += 1
            }
        }
        return out
    }

    /// Keeps `context` unchanged lines next to each change and counts the rest. A run is folded only when that hides
    /// two lines or more: "1 line skipped" takes the same room as the line.
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

    /// A text's lines; the newline that ends the last line doesn't start another.
    public static func split(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }
}
