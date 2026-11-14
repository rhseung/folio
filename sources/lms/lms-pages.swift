import FolioDomain
import Foundation
import SwiftSoup

public enum LMSPages {
    public static func classrooms(_ html: String) throws -> [LMSClassroom] {
        let doc = try SwiftSoup.parse(html)
        var seen = Set<Int>()
        return try doc.select(".course_box a.course_link").array().compactMap { a in
            guard let id = query(try a.attr("href"), "id"), id != 1, seen.insert(id).inserted else { return nil }
            let heading = try a.select(".course-title h3").first()
            try heading?.select(".new").remove()
            let title = try heading?.text() ?? a.text()
            let labels = try a.select(".course-label .label-course").array().map { try $0.text() }.filter { !$0.isEmpty }
            let professors = try a.select(".course-title .prof").first()?.text()
            return LMSClassroom(id: id, title: title, kind: labels.first, professors: professors?.isEmpty == false ? professors : nil)
        }
    }

    public static func assignments(_ html: String, classroom: Int) throws -> [LMSAssignment] {
        try rows(html).compactMap { cells in
            guard cells.count >= 4, let link = try cells[1].select("a[href]").first(),
                let id = query(try link.attr("href"), "id")
            else { return nil }
            let due = try time(cells[2].text())
            let submitted = try ["제출 완료", "Submitted for grading", "Submitted"].contains(cells[3].text())
            return LMSAssignment(id: id, classroom: classroom, title: try link.text(), due: due, submitted: submitted)
        }
    }

    // Moodle 3.2 과제 보기는 소개 첨부를 파일 트리(`#intro` 아래 `assign_files_tree…`)로 그리고, 링크는 모두
    // `mod_assign/introattachment`의 pluginfile 주소다. 트리 모양 대신 주소로 고르면 Coursemos가 트리를 바꿔도 읽힌다.
    public static func attachments(_ html: String) throws -> [LMSAttachment] {
        let doc = try SwiftSoup.parse(html)
        var seen = Set<String>()
        return try doc.select("a[href*=/mod_assign/introattachment/]").array().compactMap { a in
            guard let url = URL(string: try a.attr("href"), relativeTo: LMS.base), seen.insert(url.path).inserted else { return nil }
            let text = try a.text().trimmingCharacters(in: .whitespaces)
            let name = url.lastPathComponent.isEmpty ? text : url.lastPathComponent
            guard !name.isEmpty else { return nil }
            var path = url.path(percentEncoded: true)
            if let query = url.query(percentEncoded: true) { path += "?" + query }
            return LMSAttachment(name: name, path: path)
        }
    }

    public static func files(_ html: String, classroom: Int) throws -> [LMSFile] {
        var week: String?
        return try rows(html).compactMap { cells in
            guard cells.count >= 2 else { return nil }
            let heading = try cells[0].text()
            if !heading.isEmpty { week = heading }
            guard let link = try cells[1].select("a[href]").first(), let id = query(try link.attr("href"), "id") else { return nil }
            return LMSFile(id: id, classroom: classroom, title: try link.text(), week: week)
        }
    }

    public static func notices(_ html: String, classroom: Int) throws -> [LMSNotice] {
        let doc = try SwiftSoup.parse(html)
        return try doc.select("table.ubboard_table tbody tr").array().compactMap { tr in
            let cells = try tr.select("td").array()
            guard cells.count >= 4, let link = try cells[1].select("a[href]").first() else { return nil }
            let href = try link.attr("href")
            guard let id = query(href, "bwid"), let board = query(href, "id") else { return nil }
            try link.select("strong").remove()
            let author = try cells[2].text()
            return LMSNotice(
                id: id, board: board, classroom: classroom, title: try link.text(), author: author.isEmpty ? nil : author,
                posted: try day(cells[3].text()))
        }
    }

    public static func isLogin(_ html: String) -> Bool {
        html.contains("name=\"password\"") && html.contains("/login/index.php")
    }

    static func rows(_ html: String) throws -> [[Element]] {
        let doc = try SwiftSoup.parse(html)
        let table = try doc.select("#region-main table.generaltable").first() ?? doc.select("table.generaltable").first()
        return try table?.select("tbody tr").array().map { try $0.select("td").array() } ?? []
    }

    static func query(_ href: String, _ name: String) -> Int? {
        URLComponents(string: href)?.queryItems?.first { $0.name == name }?.value.flatMap(Int.init)
    }

    static func time(_ text: String) -> Date? { parse(text, "yyyy-MM-dd HH:mm") }
    static func day(_ text: String) -> Date? { parse(text, "yyyy-MM-dd") }

    private static func parse(_ text: String, _ format: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = LMS.timeZone
        f.dateFormat = format
        return f.date(from: text.trimmingCharacters(in: .whitespaces))
    }
}
