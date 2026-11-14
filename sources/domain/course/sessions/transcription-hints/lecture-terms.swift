import Foundation

public enum LectureTerms {
    public static func terms(in text: String, limit: Int = 40) -> [String] {
        let words = text.matches(of: /[A-Za-z][A-Za-z0-9]*(?:[-'][A-Za-z0-9]+)*/).map { (text: String($0.output), range: $0.range) }
        var counts: [String: (count: Int, first: Int, forms: [String: Int])] = [:]
        func add(_ term: String, at position: Int) {
            let key = term.lowercased()
            var entry = counts[key] ?? (0, position, [:])
            entry.count += 1
            entry.forms[term, default: 0] += 1
            counts[key] = entry
        }

        for (i, word) in words.enumerated() where isTerm(word.text) {
            add(word.text, at: i)
            if i + 1 < words.count, isTerm(words[i + 1].text), words[i + 1].text.lowercased() != word.text.lowercased(),
                text[word.range.upperBound..<words[i + 1].range.lowerBound] == " "
            {
                add("\(word.text) \(words[i + 1].text)", at: i)
            }
        }

        let kept = counts.filter { key, entry in
            key.contains(" ") ? entry.count >= 2 : true
        }
        // Whisper의 프롬프트는 끝에서부터 용어를 버리므로, 동점의 순서를 사전 순서에 맡기면 같은 슬라이드가 실행마다 다른
        // 프롬프트를 만든다. 그래서 순서를 완전히 정한다. 두 낱말 용어는 그 첫 낱말보다 앞에 둔다.
        return
            kept
            .sorted { a, b in
                (a.value.count, -a.value.first, a.key.count, b.key) > (b.value.count, -b.value.first, b.key.count, a.key)
            }
            .prefix(limit)
            .map(\.value)
            .map { entry in
                entry.forms.max { a, b in a.value < b.value || (a.value == b.value && a.key > b.key) }!.key
            }
    }

    static func isTerm(_ word: String) -> Bool {
        let lower = word.lowercased()
        guard !stopwords.contains(lower) else { return false }
        return word.count >= 3 || (word.count == 2 && word == word.uppercased())
    }

    static let stopwords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "had", "her", "was", "one", "our", "out", "has",
        "have", "him", "his", "how", "its", "may", "new", "now", "old", "see", "two", "way", "who", "did", "get", "let", "say",
        "she", "too", "use", "used", "using", "with", "this", "that", "from", "they", "will", "would", "there", "their", "what",
        "when", "which", "where", "while", "then", "than", "them", "these", "those", "into", "onto", "also", "each", "only",
        "some", "such", "more", "most", "other", "over", "same", "very", "just", "about", "after", "before", "between", "both",
        "does", "done", "here", "must", "should", "could", "been", "being", "were", "your", "yours", "ours", "via", "per",
        "is", "of", "to", "in", "on", "at", "by", "or", "an", "as", "be", "if", "it", "we", "so", "no", "do", "up",
        "page", "slide", "slides", "lecture", "chapter", "section", "figure", "fig", "example", "exercise", "note", "notes",
        "http", "https", "www", "com", "org", "edu", "pdf", "etc",
    ]
}
