import FolioDomain
import FolioStorage
import Foundation

@Action(
    "problem collect", "고른 문제로 문제집과 풀이집 PDF를 Tectonic으로 만들어 Study에 둔다",
    discussion: "문제집은 문제마다 풀이 자리를 둔 PDF이고, 풀이집은 같은 문제 아래에 답과 풀이를 둔 PDF다. 그림은 문제지 PDF에서 잘라 온다.",
    done: "'{course}'의 문제집과 풀이집을 만들었습니다", examples: [#"folio problem collect EC4207 --set "EC4207/Exercise 1""#],
    phrases: ["문제집 만들기", "문제집 PDF", "풀이집 만들기", "시험 대비 문제집", "필기로 풀 문제"], panel: true)
public struct ProblemCollectionBuild {
    /// 과목
    @Arg var course: Course.ID
    /// 넣을 묶음. 빼면 모든 묶음
    @CLIName("set") var sets: [ProblemSet.ID] = []
    /// 넣을 문제의 ID. 앱의 풀기 화면이 고른 문제를 넘긴다
    @Hidden var problems: [UUID] = []
    /// 앱이 빌드해 둔 문제집 PDF. 빌드 출력 폴더 밖의 파일은 받지 않는다. 빼면 직접 빌드한다
    @Hidden var pdf: String?
    /// 앱이 빌드해 둔 풀이집 PDF
    @Hidden var solutionsPDF: String?
    /// 같은 이름의 PDF가 Folio가 만든 것이 아니어도 바꾼다
    var overwrite = false

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        for set in sets { _ = try index(set, in: file.problemSets, .valueProblemSet) }
        let files = ProblemCollectionFiles(
            store: store, file: file, semester: try ctx.semester(of: file.course), author: try ctx.settings().study.coverName,
            problems: problems, sets: sets)
        guard files.collection.problemCount > 0 else { throw ActionError.rule(String(localized: .errorCollectionEmpty)) }

        // 사용자가 손으로 만든 문제집이 같은 이름이면 덮어쓰지 않는다. 이 액션이 만든 PDF는 해시(`builtHash`)로 알아본다.
        let targets = [files.problemsPath, files.solutionsPath]
        var replaces: [String: Bool] = [:]
        var changes: [Change] = []
        for target in targets {
            let exists = FileManager.default.fileExists(atPath: store.fileURL(target).path)
            let made = file.materials.first { $0.path == target }?.builtHash
            let ours = try exists && made != nil && made == store.hash(target)
            if exists, !ours, !overwrite { throw ActionError.conflict(String(localized: .errorBuildWouldReplace(target))) }
            replaces[target] = exists && !ours
            changes.append(Change(exists ? .changed : .added, try ctx.relative(course, target)))
        }
        guard !ctx.dryRun else {
            changes.forEach(ctx.record)
            return
        }

        let built: [URL]
        if let pdf, let solutionsPDF {
            built = [try MaterialBuild.output(pdf, of: files.problemsTeX), try MaterialBuild.output(solutionsPDF, of: files.solutionsTeX)]
        } else {
            let made = try files.build(at: ctx.now, calendar: ctx.calendar)
            built = [made.problems, made.solutions]
        }
        for (target, (source, change)) in zip(targets, zip(built, changes)) {
            try ctx.io(change) {
                try FileManager.default.createDirectory(
                    at: store.fileURL(target).deletingLastPathComponent(), withIntermediateDirectories: true)
                try store.replaceFile(target, with: source, keepOld: replaces[target] ?? false)
            }
        }

        try ctx.edit(course) { f in
            try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now)
            var ids: [UUID] = []
            for target in targets {
                guard let i = f.materials.firstIndex(where: { $0.path == target }) else { continue }
                try store.rehash(f.materials[i].id, in: &f, device: ctx.device, now: ctx.now)
                f.materials[i].builtHash = f.materials[i].hash
                ids.append(f.materials[i].id)
            }
            if ids.count == 2, let i = f.materials.firstIndex(where: { $0.id == ids[1] }), f.materials[i].solutionOf != ids[0] {
                f.materials[i].solutionOf = ids[0]
                f.materials[i].touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
