import Foundation

// 자료에서 문제를 뽑을지, 어떤 출처로 볼지, 해설 파일이 무엇인지, 뽑은 문제를 어느 단원에 이을지를 정한다. 앱의 저절로
// 뽑기, 자료 메뉴, `problem-set propose`가 같은 규칙을 읽는다.
public enum ProblemExtraction {
    // Claude API가 한 요청에 받는 PDF의 쪽 수 한도다. 이보다 긴 교재는 저절로 보내지 않는다.
    public static let automaticPageLimit = 100

    // 손으로 뽑을 수 있는 자료다. 문제지는 PDF이거나 `.tex` 원본이다.
    public static func accepts(_ m: Material) -> Bool {
        !m.isFolder && m.status != .missing && m.status != .ignored && (m.isPDF || m.format == .tex) && !isSolution(m)
            && m.kind != .submission
    }

    // 새로 등록된 자료 중 저절로 뽑는 것이다. `Inherited`는 선배의 노트도 담으므로 시험지로 보이는 파일만 뽑는다.
    public static func automatic(_ m: Material, in file: CourseFile) -> Bool {
        guard accepts(m), m.isPDF, !excludedKinds.contains(m.kind), !extracted(m, in: file) else { return false }
        switch folder(of: m) {
        case .inherited: return m.kind == .pastExam || (m.kind == nil && looksLikeExam(m.path))
        case .textbooks, .exercises, .assignments: return true
        default: return false
        }
    }

    public static func extracted(_ m: Material, in file: CourseFile) -> Bool {
        file.problemSets.contains { $0.materialId == m.id || $0.solutionMaterialId == m.id }
    }

    public static func source(of m: Material) -> ProblemSource {
        switch folder(of: m) {
        case .inherited, .exams: .pastExam
        case .textbooks: .textbook
        case .assignments: .assignment
        default: m.kind == .pastExam ? .pastExam : .exercise
        }
    }

    // 문제 묶음의 제목은 파일 이름에서 확장자를 뺀 것이다. 과제 폴더의 파일은 과제 이름을 앞에 붙인다. 과제 폴더 안의
    // 파일 이름은 교수가 정한 것이라 "problem.pdf"처럼 과제를 말하지 않기 때문이다.
    public static func title(of m: Material) -> String {
        let parts = m.path.split(separator: "/").map(String.init)
        let stem = ((parts.last ?? m.path) as NSString).deletingPathExtension
        if parts.first == CourseFolder.assignments.rawValue, parts.count > 2, !stem.localizedCaseInsensitiveContains(parts[1]) {
            return "\(parts[1]) \(stem)"
        }
        return stem
    }

    public static func isSolution(_ m: Material) -> Bool {
        m.kind == .solution || m.solutionOf != nil || NameWords(m.path).hasMarker
    }

    // 사용자가 이은 해설(`solutionOf`)이 먼저이고, 없으면 같은 폴더에서 해설 표시만 다른 이름의 파일이다.
    // "2022 중간.pdf"와 "2022 중간 해설.pdf", "HW3.pdf"와 "HW3_sol.pdf"가 짝이다.
    public static func solution(for sheet: Material, in materials: [Material]) -> Material? {
        if let linked = materials.first(where: { $0.solutionOf == sheet.id && !$0.isFolder }) { return linked }
        let folder = (sheet.path as NSString).deletingLastPathComponent, words = NameWords(sheet.path)
        return materials.first { m in
            m.id != sheet.id && !m.isFolder && (m.isPDF || m.format == .tex) && (m.path as NSString).deletingLastPathComponent == folder
                && NameWords(m.path).hasMarker && NameWords(m.path).stem == words.stem
        }
    }

    // Claude가 단원을 적지 않은 문제는 고른 렉처 쪽이 든 단원에 잇는다. 쪽이 여러 단원에 들면 가장 깊은 단원이다. 렉처 쪽도
    // 없으면 문제지 자료가 바로 이어진 단원이 하나일 때 그 단원에 잇는다. 단원의 쪽 구간 밖의 렉처 쪽은 버린다. Claude가
    // 단원의 쪽 구간에서 고르게 했으므로 밖의 쪽은 잘못 읽은 것이다.
    public static func linked(_ problems: [Problem], units: [Unit], sheet: Material?) -> [Problem] {
        let outline = UnitTree.outline(units)
        let fallback = sheet.map { m in m.unitIds.filter { id in units.contains { $0.id == id } } } ?? []
        return problems.map { p in
            var p = p
            p.lecturePages = p.lecturePages.filter { page in !holders(of: page, in: outline).isEmpty }
            if p.unitIds.isEmpty {
                let found = p.lecturePages.flatMap { holders(of: $0, in: outline) }
                let deepest = found.map(\.depth).max()
                var ids: [UUID] = []
                for row in found where row.depth == deepest && !ids.contains(row.unit.id) { ids.append(row.unit.id) }
                p.unitIds = ids.isEmpty && fallback.count == 1 ? fallback : ids
            }
            return p
        }
    }

    private static func holders(of page: ProblemPage, in outline: [(unit: Unit, depth: Int)]) -> [(unit: Unit, depth: Int)] {
        outline.filter { row in row.unit.lecturePages.contains { $0.materialId == page.materialId && $0.pages.contains(page.page) } }
    }

    private static let excludedKinds: Set<MaterialKind?> = [.solution, .submission, .slides, .syllabus]

    private static func folder(of m: Material) -> CourseFolder? {
        m.path.split(separator: "/").first.flatMap { CourseFolder(rawValue: String($0)) }
    }

    private static func looksLikeExam(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        return examWords.contains { name.contains($0) }
    }

    private static let examWords = [  // strings: data, 파일 이름과 비교하는 낱말
        "기출", "족보", "중간", "기말", "퀴즈", "시험", "midterm", "final", "quiz", "exam",
    ]
}

// 파일 이름의 낱말이다. 해설 표시를 빼고 비교하려고 쓴다.
private struct NameWords {
    var words: [String]
    var hasMarker: Bool

    init(_ path: String) {
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        var marker = false
        words = stem.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap { word -> String? in
            var w = String(word)
            if Self.markers.contains(w) {
                marker = true
                return nil
            }
            // 한국어는 "중간해설"처럼 붙여 쓰기도 한다.
            if let suffix = Self.koreanMarkers.first(where: { w.hasSuffix($0) && w.count > $0.count }) {
                marker = true
                w.removeLast(suffix.count)
            }
            return w
        }
        hasMarker = marker
    }

    var stem: String { words.joined(separator: " ") }

    static let koreanMarkers = ["해설", "풀이", "정답", "답안"]  // strings: data, 파일 이름과 비교하는 낱말
    static let markers: Set<String> = Set(
        koreanMarkers + [  // strings: data, 파일 이름과 비교하는 낱말
            "sol", "sols", "soln", "solution", "solutions", "answer", "answers", "key",
        ])
}
