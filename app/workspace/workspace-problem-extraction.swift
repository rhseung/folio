import FolioAI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import PDFKit

extension Workspace {
    // 자료 메뉴의 "문제 뽑기"다. 결과는 문제 페이지의 알림 카드로 받는다.
    func extractProblems(from material: UUID, in courseId: UUID) {
        guard let course = course(courseId) else { return }
        guard let client = extractionClient(for: course) else {
            error = String(localized: .problemExtractNoClaude)
            return
        }
        extractor.enqueue(material) { [weak self] in try await self?.extract(material, in: courseId, client: client, automatic: false) }
    }

    // 액션이 새로 등록한 자료 중 문제지를 저절로 뽑는다. 자료 페이지의 자동 등록, 파일 들여오기, LMS 받기가 모두 이 길로 온다.
    // 다른 기기나 CLI가 등록한 자료는 그 쪽이 등록한 것이라 이 기기가 뽑지 않는다.
    func extractNewSheets(_ added: [UUID], in courseId: UUID) {
        guard settings.study.autoExtract, let course = course(courseId), let client = extractionClient(for: course) else { return }
        let drafts = Set(((try? course.store.drafts()) ?? []).compactMap(\.model.materialId))
        for id in added where extractor.state(of: id) == nil && !drafts.contains(id) {
            guard let m = course.file.materials.first(where: { $0.id == id }), ProblemExtraction.automatic(m, in: course.file) else {
                continue
            }
            extractor.enqueue(id) { [weak self] in try await self?.extract(id, in: courseId, client: client, automatic: true) }
        }
    }

    private func extractionClient(for course: LoadedCourse) -> ClaudeClient? {
        if let standIn = extractor.standIn { return standIn(course) }
        return claudeReady ? claude(for: course) : nil
    }

    private func extract(_ materialId: UUID, in courseId: UUID, client: ClaudeClient, automatic: Bool) async throws {
        guard let course = course(courseId), let sheet = course.file.materials.first(where: { $0.id == materialId }) else { return }
        let file = course.file, store = course.store
        let solution = ProblemExtraction.solution(for: sheet, in: file.materials)
        let read = try await Task.detached { () throws -> ExtractionInput? in
            let document = try Self.document(sheet, store: store)
            // 저절로 뽑기는 Claude가 한 번에 받지 못하는 긴 교재를 건너뛴다. 손으로 뽑으면 Claude의 거절을 그대로 보인다.
            if automatic, case .pdf(let data) = document,
                (PDFDocument(data: data)?.pageCount ?? 0) > ProblemExtraction.automaticPageLimit
            {
                return nil
            }
            return ExtractionInput(
                sheet: document, solution: try solution.map { try Self.document($0, store: store) }, lectures: store.lectureOutline(file))
        }.value
        guard let read else { return }
        let problems = try await client.extractProblems(
            sheet: read.sheet, solution: read.solution, units: file.units, lectures: read.lectures,
            source: ProblemExtraction.source(of: sheet))
        guard !problems.isEmpty else { throw ActionError.rule(String(localized: .problemExtractEmpty)) }
        _ = try runThrowing(ProblemSetPropose(course: courseId, material: materialId, solution: solution?.id, problems: problems))
    }

    nonisolated private static func document(_ m: FolioDomain.Material, store: CourseStore) throws -> ProblemDocument {
        let data = try store.contents(of: m)
        guard m.format == .tex else { return .pdf(data) }
        guard let text = String(bytes: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return .tex(text)
    }
}

private struct ExtractionInput: Sendable {
    var sheet: ProblemDocument
    var solution: ProblemDocument?
    var lectures: LectureOutline
}
