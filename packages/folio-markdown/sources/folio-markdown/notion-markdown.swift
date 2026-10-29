import Foundation

/// Math (`$…$`, `$$…$$`), headings, lists and tables are already compatible and pass through.
public enum NotionMarkdown {
    /// - Parameters:
    ///   - links: Notion page ID (32 lowercase hex, no dashes) → note title, so mentions of imported pages become `[[title]]`.
    ///   - images: the exact `source` attribute of an `<image>` → path relative to the note. Missing ones are dropped.
    public static func convert(_ text: String, links: [String: String] = [:], images: [String: String] = [:]) -> String {
        var out: [String] = []
        var depth = 0
        // How the next line decides the title of a just-opened quote block.
        enum Pending { case boldTitle(String, Bool), summary, firstLine, obsidianCallout }
        var pending: (kind: Pending, depth: Int)?
        var afterHeader = false
        // HTML lists inside markdown list items: marker and indentation per open list.
        var lists: [(indent: String, ordered: Bool, count: Int)] = []
        var bullet: String?
        var table: (indent: String, rows: [[String]], cell: [String]?)?

        func emit(_ line: String, at level: Int) {
            let quote = String(repeating: "> ", count: level)
            out.append(level == 0 ? line : line.isEmpty ? String(quote.dropLast()) : quote + line)
        }
        func header(_ type: String, folded: Bool, title: String, at level: Int) {
            emit("[!\(type)]\(folded ? "-" : "")" + (title.isEmpty ? "" : " \(title)"), at: level)
            afterHeader = true
        }
        func settle() {
            guard let p = pending else { return }
            pending = nil
            switch p.kind {
            case .boldTitle(let type, let folded): header(type, folded: folded, title: "", at: p.depth)
            case .summary, .firstLine: header("note", folded: true, title: "", at: p.depth)
            case .obsidianCallout: break
            }
        }
        func line(_ s: String) -> String { inline(s, links: links, images: images) }

        for raw in text.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let indent = String(raw.prefix { $0 == " " || $0 == "\t" })

            if var t = table {
                if trimmed.hasPrefix("</table") {
                    table = nil
                    for (i, row) in t.rows.enumerated() {
                        emit(t.indent + "| " + row.joined(separator: " | ") + " |", at: depth)
                        if i == 0 { emit(t.indent + "|" + Array(repeating: " --- |", count: row.count).joined(), at: depth) }
                    }
                } else if trimmed == "<tr>" {
                    t.rows.append([])
                    table = t
                } else if let m = trimmed.wholeMatch(of: /<t[dh][^>]*>(.*)<\/t[dh]>/) {
                    t.rows[t.rows.count - 1].append(cell(line(String(m.1))))
                    table = t
                } else if trimmed.hasPrefix("<td") || trimmed.hasPrefix("<th") {
                    t.cell = []
                    table = t
                } else if trimmed == "</td>" || trimmed == "</th>" {
                    if !t.rows.isEmpty { t.rows[t.rows.count - 1].append(cell((t.cell ?? []).joined(separator: " "))) }
                    t.cell = nil
                    table = t
                } else if t.cell != nil, !trimmed.isEmpty {
                    t.cell!.append(line(trimmed))
                    table = t
                }
                continue
            }
            if trimmed.hasPrefix("<table") {
                settle()
                table = (indent, [], nil)
                continue
            }

            if let m = trimmed.wholeMatch(of: /<callout([^>]*)>/) {
                settle()
                depth += 1
                pending = (.boldTitle(calloutType(attributes: String(m.1)), false), depth)
                continue
            }
            if trimmed == "<details>" || trimmed.hasPrefix("<details ") {
                settle()
                depth += 1
                pending = (.summary, depth)
                continue
            }
            if trimmed == "<toggle>" || trimmed.hasPrefix("<toggle ") {
                settle()
                depth += 1
                pending = (.firstLine, depth)
                continue
            }
            if trimmed == "<quote>" || trimmed.hasPrefix("<quote ") {
                settle()
                depth += 1
                pending = (.obsidianCallout, depth)
                continue
            }
            if ["</callout>", "</details>", "</toggle>", "</quote>"].contains(trimmed) {
                settle()
                depth = max(0, depth - 1)
                afterHeader = false
                // Without a break the next quote block would join this one.
                emit("", at: depth)
                continue
            }
            if let m = trimmed.wholeMatch(of: /<(ul|ol)[^>]*>/) {
                lists.append((indent, m.1 == "ol", 0))
                continue
            }
            if trimmed == "</ul>" || trimmed == "</ol>" {
                _ = lists.popLast()
                continue
            }
            if trimmed.hasPrefix("<li"), !lists.isEmpty {
                lists[lists.count - 1].count += 1
                let l = lists[lists.count - 1]
                bullet = l.indent + (l.ordered ? "\(l.count). " : "- ")
                if let m = trimmed.wholeMatch(of: /<li[^>]*>(.+)<\/li>/) {
                    emit(bullet! + line(String(m.1)), at: depth)
                    bullet = nil
                }
                continue
            }
            if trimmed == "</li>" { bullet = nil; continue }

            if let p = pending, !trimmed.isEmpty {
                switch p.kind {
                case .boldTitle(let type, let folded):
                    if let m = trimmed.wholeMatch(of: /<b>(.*)<\/b>/) {
                        pending = nil
                        header(type, folded: folded, title: line(String(m.1)), at: p.depth)
                        continue
                    }
                case .summary:
                    if let m = trimmed.wholeMatch(of: /<summary>(.*)<\/summary>/) {
                        pending = nil
                        header("note", folded: true, title: line(String(m.1)), at: p.depth)
                        continue
                    }
                case .firstLine:
                    pending = nil
                    header("note", folded: true, title: line(trimmed), at: p.depth)
                    continue
                case .obsidianCallout:
                    // Obsidian callouts pasted into Notion arrive as quotes with an escaped `\[!type\]` first line.
                    if let m = trimmed.wholeMatch(of: /\\?\[!([A-Za-z-]+)\\?\]([+-]?)\s*(.*)/) {
                        pending = nil
                        header(String(m.1).lowercased(), folded: m.2 == "-", title: line(String(m.3)), at: p.depth)
                        continue
                    }
                }
            }
            if dropped.contains(trimmed) || trimmed.wholeMatch(of: droppedLine) != nil { continue }
            if trimmed.isEmpty, pending != nil || afterHeader { continue }
            settle()
            afterHeader = false
            if trimmed == "<empty-block/>" {
                emit("", at: depth)
            } else if let b = bullet {
                emit(b + line(trimmed), at: depth)
                bullet = String(repeating: " ", count: b.count)
            } else {
                // Toggle children are tab-indented under their title.
                emit(line(depth > 0 && raw.hasPrefix("\t") ? String(raw.dropFirst()) : raw), at: depth)
            }
        }
        settle()
        return out.joined(separator: "\n")
    }

    /// Wrapper tags with no Folio counterpart; their content stays.
    static let dropped: Set<String> = ["<p>", "</p>", "<p />", "<p/>", "<columns>", "</columns>", "<column>", "</column>", "</pdf>", "</image>"]
    static var droppedLine: Regex<Substring> { /<(?:table-of-contents|p|column|columns)\b[^>]*\/?>/ }

    static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").trimmingCharacters(in: .whitespaces)
    }

    static func calloutType(attributes: String) -> String {
        let icon = attributes.firstMatch(of: /icon="([^"]*)"/).map { String($0.1) } ?? ""
        switch icon {
        case "⚠️", "❗", "🚨", "‼️", "⛔": return "warning"
        case "💡": return "tip"
        case "❓", "🤔": return "question"
        case "📌", "ℹ️", "📎": return "info"
        case "🔥", "⭐": return "important"
        default: return "note"
        }
    }

    static func inline(_ line: String, links: [String: String], images: [String: String]) -> String {
        var s = line
        s.replace(/<image\s+source="([^"]*)"[^>]*?(?:\/>|>(.*?)<\/image>|>)/) { m in
            images[String(m.1)].map { "![\(m.2.map(String.init) ?? "")](\($0))" } ?? ""
        }
        s.replace(/<mention-page\s+url="([^"]*)"[^>]*?(?:\/>|>(.*?)<\/mention-page>)/) { m in mention(String(m.1), text: m.2.map(String.init), links: links) }
        s.replace(/<mention\s+url="([^"]*)"[^>]*?(?:\/>|>(.*?)<\/mention>)/) { m in mention(String(m.1), text: m.2.map(String.init), links: links) }
        s.replace(/<pdf\s+source="([^"]*)"[^>]*?(?:\/>|>(.*?)<\/pdf>|>)/) { m in
            images[String(m.1)].map { "[\(($0 as NSString).lastPathComponent)](\($0))" } ?? ""
        }
        // Mentions sometimes arrive already as markdown links to the Notion page.
        s.replace(/\[([^\]]*)\]\((https?:\/\/(?:app\.notion\.com|(?:www\.)?notion\.so)\/[^)\s]*)\)/) { m in
            guard let id = m.2.firstMatch(of: /[0-9a-f]{32}/).map({ String($0.0) }), let title = links[id] else { return String(m.0) }
            return m.1 == title || m.1.isEmpty ? "[[\(title)]]" : "[[\(title)|\(m.1)]]"
        }
        s.replace(/<(?:mention-date|date)\s+start="([^"]*)"[^>]*?\/>/) { m in String(m.1) }
        s.replace(/<b>(.*?)<\/b>/) { m in "**\(m.1)**" }
        s.replace(/<strong>(.*?)<\/strong>/) { m in "**\(m.1)**" }
        s.replace(/<(?:i|em)>(.*?)<\/(?:i|em)>/) { m in "*\(m.1)*" }
        s.replace(/<s>(.*?)<\/s>/) { m in "~~\(m.1)~~" }
        s.replace(/<code>(.*?)<\/code>/) { m in "`\(m.1)`" }
        s.replace(/<u>(.*?)<\/u>/) { m in String(m.1) }
        s.replace(/<span[^>]*>(.*?)<\/span>/) { m in String(m.1) }
        s.replace(/<p\b[^>]*>(.*?)<\/p>/) { m in String(m.1) }
        s.replace(/<br\s*\/?>/) { _ in " " }
        return s
    }

    static func mention(_ url: String, text: String?, links: [String: String]) -> String {
        if let id = url.firstMatch(of: /[0-9a-f]{32}/).map({ String($0.0) }), let title = links[id] {
            return "[[\(title)]]"
        }
        return "[\(text?.isEmpty == false ? text! : "링크")](\(url))"
    }
}
