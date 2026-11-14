import Foundation

enum Keywords {
    static let syllabus = ["syllabus", "강의계획서", "수업계획서", "orientation", "스케줄", "schedule", "클리닉", "clinic"]
    static let textbook = ["textbook", "교재", "edition", "solution manual", "introduction to"]
    static let examFiles: [(name: String, words: [String])] = [
        ("Guideline", ["guideline", "시험 안내", "시험안내"]),
        ("Seating", ["seating", "자리", "좌석"]),
    ]

    static var midterm: Regex<Substring> { #/mid[\s_-]?term|midterm|mid|중간고사|중간/# }
    static var final: Regex<Substring> { #/final[\s_-]?(?:term|exam)|final|기말고사|기말/# }

    static let defaultExam = StandardLayout.midtermFolder

    static func examFolder(in lower: String) -> String? {
        if let m = lower.firstMatch(of: /(?:quiz|퀴즈)[\s_-]*(\d{1,2})(?!\d)/) { return StandardLayout.quizFolderPrefix + String(Int(m.1)!) }
        if lower.contains(midterm) { return StandardLayout.midtermFolder }
        if lower.contains(final) { return StandardLayout.finalFolder }
        return nil
    }

    // 교수의 `review.pdf`에도 이런 낱말이 있으므로, 언제나 제안으로만 쓴다.
    static func looksSelfMade(_ name: String) -> Bool {
        name.lowercased().contains(/대비|정리|요약|압축|summary|cheat[\s_-]?sheet|mock|모의/)
    }

    static func week(in name: String) -> (week: Int, leading: Bool?, review: ReviewReason?)? {
        let lower = name.lowercased()
        if let m = lower.firstMatch(of: /(?:week|wk)[\s_-]*(\d{1,2})(?!\d)/) ?? lower.firstMatch(of: /(\d{1,2})\s*주차/) {
            return (Int(m.1)!, false, nil)
        }
        if let m = lower.firstMatch(of: /^(\d{1,2})[\s_.-]/) {
            return (Int(m.1)!, true, .guessedWeek)
        }
        if let m = lower.firstMatch(of: /(?:lecture|lec|chapter|ch)[\s_-]*(\d{1,2})(?!\d)/) {
            return (Int(m.1)!, false, .guessedWeek)
        }
        return nil
    }

    static func title(of name: String, stripping leading: Bool?) -> (base: String, ext: String) {
        let ns = name as NSString
        var base = ns.deletingPathExtension
        if leading == true, let m = base.firstMatch(of: /^\d{1,2}[\s_.-]+/) {
            base.removeSubrange(m.range)
        }
        return (base, ns.pathExtension.isEmpty ? "" : "." + ns.pathExtension)
    }

    // `recrystallization`이 `point`보다 많은 것을 말하므로, 겹친 낱말은 길이로 가중한다.
    static func labNumber(of name: String, labs: [String: Int]) -> Int? {
        let file = words(name)
        let scores = labs.map { (number: $0.value, score: words($0.key).intersection(file).reduce(0) { $0 + $1.count }) }
        guard let best = scores.map(\.score).max(), best > 0 else { return nil }
        let numbers = Set(scores.filter { $0.score == best }.map(\.number))
        return numbers.count == 1 ? numbers.first : nil
    }

    static let labStopWords: Set<String> = [
        "and", "of", "the", "a", "an", "in", "using", "lab", "pre", "prelab", "report", "manual", "pdf",
    ]

    static func words(_ text: String) -> Set<String> {
        let lower = (text as NSString).deletingPathExtension.lowercased().replacingOccurrences(of: "&", with: " and ")
        return Set(
            lower.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.map(String.init)
                .filter { !labStopWords.contains($0) && !$0.allSatisfy(\.isNumber) })
    }

    static func assignmentNumber(in name: String) -> (number: Int, review: ReviewReason?)? {
        let lower = name.lowercased()
        let keyword = /(?:hw|homework|assignment|assign|pa|lab|sp|slow[\s_-]?problems?|report|project|과제|숙제)[\s_-]*(\d{1,2})(?!\d)/
        if let m = lower.firstMatch(of: keyword) ?? lower.firstMatch(of: /\d{2}h(\d{1,2})(?!\d)/) {
            return (Int(m.1)!, nil)
        }
        if let m = lower.firstMatch(of: /^(\d{1,2})[\s_.-]/) {
            return (Int(m.1)!, .guessedNumber)
        }
        return nil
    }
}
