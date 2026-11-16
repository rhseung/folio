import Foundation

enum Keywords {
    static var midterm: Regex<Substring> { #/mid[\s_-]?term|midterm|mid|중간고사|중간/# }
    static var final: Regex<Substring> { #/final[\s_-]?(?:term|exam)|final|기말고사|기말/# }

    static let defaultExam = StandardLayout.midtermFolder

    // Swift Regex의 `\d`는 전각 숫자(`２`)에도 맞지만 `Int("２")`는 nil이다. 번호를 읽는 정규식은 모두 ASCII 숫자로 좁힌다.
    static func examFolder(in lower: String) -> String? {
        if let m = lower.firstMatch(of: /(?:quiz|퀴즈)[\s_-]*(\d{1,2})(?!\d)/.asciiOnlyDigits()), let n = Int(m.1) {
            return StandardLayout.quizFolderPrefix + String(n)
        }
        if lower.contains(midterm) { return StandardLayout.midtermFolder }
        if lower.contains(final) { return StandardLayout.finalFolder }
        return nil
    }

    static func mentionsLab(_ name: String, kinds: [AssignmentKind]) -> Bool {
        guard let lab = kinds.first(where: { $0 == .lab }),
            let regex = try? Regex("(?:" + FileRule.alternation(lab.words) + #")\s*\d"#)
        else { return false }
        return name.lowercased().firstMatch(of: regex) != nil
    }

    static func looksSelfMade(_ name: String) -> Bool {
        FileRule.rules(for: .cleanup).contains { $0.kind == .selfMade && $0.match(name) != nil }
    }

    // 자료 추측과 같은 주차 낱말을 읽는다. 다만 예전 폴더의 `lecture 3`, `ch3`은 주차가 아니라 차례일 수 있어 검토로 남긴다.
    static func week(in name: String) -> (week: Int, leading: Bool?, review: ReviewReason?)? {
        if let m = FileRule.numbered(FileRule.weekWords, in: name) ?? FileRule.koreanWeek(in: name) {
            return (m.number, false, nil)
        }
        if let m = name.firstMatch(of: /^(\d{1,2})[\s_.-]/), let week = Int(m.1) {
            return (week, true, .guessedWeek)
        }
        if let m = FileRule.numbered(FileRule.lectureWords + FileRule.chapterWords, in: name) {
            return (m.number, false, .guessedWeek)
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

    // 예전 폴더의 이름은 낱말이 붙어 있어(`gthw2`) 자료 추측과 달리 낱말 앞의 경계를 보지 않는다.
    static func assignmentNumber(in name: String, kinds: [AssignmentKind] = AssignmentKind.builtIn) -> (number: Int, review: ReviewReason?)?
    {
        let lower = name.lowercased()
        let words = kinds.flatMap(\.words)
        let keyword =
            words.isEmpty
            ? nil
            : (try? Regex<(Substring, Substring)>("(?:" + FileRule.alternation(words) + #")[\s_-]*(\d{1,2})(?!\d)"#))?.asciiOnlyDigits()
        if let m = keyword.flatMap({ lower.firstMatch(of: $0) }) ?? lower.firstMatch(of: /\d{2}h(\d{1,2})(?!\d)/.asciiOnlyDigits()),
            let n = Int(m.1)
        {
            return (n, nil)
        }
        if let m = lower.firstMatch(of: /^(\d{1,2})[\s_.-]/.asciiOnlyDigits()), let n = Int(m.1) {
            return (n, .guessedNumber)
        }
        return nil
    }
}
