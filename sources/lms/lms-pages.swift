import FolioDomain
import Foundation
import SwiftSoup

/// Reads the Coursemos pages (theme `coursemosv2`) into LMS values. The selectors were read from the logged-in pages
/// on 2026-11-13; a Coursemos update can change them, and a page that stops matching reads as empty rather than wrong.
public enum LMSPages {
    /// The dashboard's course boxes: `.course_box a.course_link` holding labels, the title and the professors.
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

    /// `mod/assign/index.php?id=<classroom>`: week, title (linked), deadline, submission, grade. The week cell is
    /// filled only on a week's first row, and weeks are split by divider rows.
    public static func assignments(_ html: String, classroom: Int) throws -> [LMSAssignment] {
        try rows(html).compactMap { cells in
            guard cells.count >= 4, let link = try cells[1].select("a[href]").first(),
                let id = query(try link.attr("href"), "id")
            else { return nil }
            let due = try time(cells[2].text())
            // Moodle's own words: anything but these counts as not handed in.
            let submitted = try ["제출 완료", "Submitted for grading", "Submitted"].contains(cells[3].text())
            return LMSAssignment(id: id, classroom: classroom, title: try link.text(), due: due, submitted: submitted)
        }
    }

    /// `mod/ubfile/index.php?id=<classroom>`: week, title (linked), description.
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

    /// `mod/ubboard/my.php?mc=<classroom>`: number, title (linked, after the classroom's name in brackets), author,
    /// date, views.
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

    /// Whether a page is the login form, which every page turns into once the session is gone.
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
