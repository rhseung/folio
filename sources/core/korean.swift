import Foundation

public enum Korean {
    static func hasFinalConsonant(_ word: String) -> Bool {
        guard let last = word.unicodeScalars.last(where: { !CharacterSet.whitespaces.contains($0) }),
            (0xAC00...0xD7A3).contains(last.value)
        else { return false }
        return (last.value - 0xAC00) % 28 != 0
    }

    public static func quoted(_ word: String, _ afterConsonant: String, _ afterVowel: String) -> String {
        "'\(word)'" + (hasFinalConsonant(word) ? afterConsonant : afterVowel)
    }

    public static func subject(_ word: String) -> String { word + (hasFinalConsonant(word) ? "이" : "가") }
    public static func object(_ word: String) -> String { word + (hasFinalConsonant(word) ? "을" : "를") }
}
