import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class TextFileModel {
    enum Source {
        case material(UUID)
        case note(NoteFile)
    }

    let workspace: Workspace
    private let initial: LoadedCourse
    let source: Source
    var text = ""
    // 여기서 마지막으로 읽거나 쓴 내용이다. 저장할 때 디스크가 이와 다르면 다른 곳(다른 기기, CLI)에서 바뀐 것이므로
    // 덮어쓰기 전에 묻는다.
    private var onDisk = ""
    private(set) var loaded = false
    private(set) var unreadable = false
    var conflict = false
    var reveal: Int?
    private(set) var building = false
    private(set) var issues: [TexIssue] = []
    // PDF는 이름이 그대로이므로, 빌드한 뒤 이 값을 올려야 미리보기가 PDF를 다시 연다.
    private(set) var pdfRevision = 0
    private var held: URL?
    var asksToReplace = false

    convenience init(workspace: Workspace, course: LoadedCourse, material: UUID) {
        self.init(workspace: workspace, course: course, source: .material(material))
    }

    init(workspace: Workspace, course: LoadedCourse, source: Source) {
        self.workspace = workspace
        initial = course
        self.source = source
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var path: String {
        switch source {
        case let .material(id): course.file.materials.first { $0.id == id }?.path ?? ""
        case let .note(note): course.store.notePath(of: note.url)
        }
    }

    var paneId: UUID? {
        switch source {
        case let .material(id): id
        case let .note(note): note.meta.id
        }
    }

    var name: String { (path as NSString).lastPathComponent }
    var format: MaterialFormat { MaterialFormat(path: path) }
    var isTex: Bool { format == .tex }
    var dirty: Bool { loaded && text != onDisk }

    // 이 화면의 링크 메뉴가 노트를 연 뒤 그 위치를 바꿀 수 있으므로, `source`에서 받지 않고 항목을 다시 읽는다.
    var pdfPath: String {
        switch source {
        case let .material(id):
            let source = course.file.materials.first { $0.id == id }
            return source.flatMap { course.file.materials.builtPDF(of: $0) }?.path ?? MaterialFormat.builtPDF(of: path) ?? path
        case let .note(note):
            return course.store.exportPath(of: course.store.note(at: path, in: course.file) ?? note)
        }
    }
    var pdfName: String { (pdfPath as NSString).lastPathComponent }
    var pdfURL: URL? {
        let url = course.store.fileURL(pdfPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var canBuild: Bool { isTex && !building }

    var fileURL: URL { course.store.fileURL(path) }
    var errors: [TexIssue] { issues.filter { $0.severity == .error } }
    var shownIssues: [TexIssue] { errors + issues.filter { $0.severity == .warning } }

    // 읽을 수 없는 파일(아직 내려받지 않았거나, 없거나, UTF-8이 아닌 파일)이면 편집기를 닫아 둔다. 빈 편집기는 빈
    // 파일처럼 보이고, 저장하면 실제 파일을 덮어쓴다.
    func load() {
        do {
            onDisk = try course.store.readText(path)
            text = onDisk
            loaded = true
            unreadable = false
        } catch {
            loaded = false
            unreadable = true
        }
    }

    // 앱 안의 다른 곳에서 쓴 자료는 course.json의 해시만 바꾸고, 노트나 앱 밖(다른 기기, CLI)에서 쓴 파일은
    // `notesRevision`을 바꾼다.
    var outsideRevision: String {
        let hash = if case let .material(id) = source { course.file.materials.first { $0.id == id }?.hash } else { String?.none }
        return "\(workspace.notesRevision) \(hash ?? "")"
    }

    func refresh() {
        guard loaded, let disk = try? course.store.readText(path), disk != onDisk else { return }
        if dirty {
            conflict = true
        } else {
            onDisk = disk
            text = disk
        }
    }

    func saveNow(force: Bool) {
        guard loaded, !conflict || force else { return }
        let writing = text
        do {
            let expected = force ? nil : onDisk
            switch source {
            case let .material(id):
                _ = try workspace.runThrowing(MaterialWrite(course: course.id, material: id, text: writing, expected: expected))
            case .note: _ = try workspace.runThrowing(NoteWrite(course: course.id, note: path, text: writing, expected: expected))
            }
            onDisk = writing
            conflict = false
        } catch ActionError.conflict {
            conflict = true
        } catch {
            workspace.error = "\(error)"
        }
    }

    func saveIfDirty() { if dirty { saveNow(force: false) } }

    // PDF가 화면의 내용을 보이도록 먼저 저장한다. Tectonic은 main thread 밖에서 돌고, 액션은 만든 PDF를 놓기만 한다.
    func build() async {
        guard canBuild else { return }
        saveIfDirty()
        guard !dirty else { return }

        building = true
        defer { building = false }
        let file = course.store.fileURL(path)
        let (now, calendar) = (workspace.now, workspace.calendar)
        let result: TexEngine.Build
        do {
            result = try await Task.detached {
                try TexEngine.shared.compile(file, into: TexEngine.outputFolder(for: file), at: now, calendar: calendar)
            }.value
        } catch {
            issues = [TexIssue(.error, message: error.localizedDescription)]
            return
        }

        issues = result.issues
        guard let pdf = result.pdf else { return }
        place(pdf, overwrite: false)
    }

    #if os(macOS)
    // 쪽은 0부터 세고, 점은 쪽의 왼쪽 위 모서리에서 잰다. `\input` 파일은 여기 열려 있지 않으므로 이 파일의 줄만
    // 다룬다.
    func showSource(page: Int, at point: CGPoint) {
        guard isTex, let shown = pdfURL, let sync = TexEngine.syncTeX(for: fileURL, showing: shown),
            let place = sync.place(page: page + 1, x: point.x, y: point.y),
            URL(filePath: place.file).resolvingSymlinksInPath() == fileURL.resolvingSymlinksInPath()
        else { return }
        reveal = place.line
    }
    #endif

    func replace() {
        guard let held else { return }
        place(held, overwrite: true)
    }

    private func place(_ pdf: URL, overwrite: Bool) {
        held = nil
        do {
            switch source {
            case let .material(id):
                _ = try workspace.runThrowing(MaterialBuild(course: course.id, material: id, pdf: pdf.path, overwrite: overwrite))
            case .note: _ = try workspace.runThrowing(NoteBuild(course: course.id, note: path, pdf: pdf.path, overwrite: overwrite))
            }
            pdfRevision += 1
        } catch ActionError.conflict {
            held = pdf
            asksToReplace = true
        } catch {
            workspace.error = "\(error)"
        }
    }

    // Tectonic은 문서 폴더에서 돌고 거기서부터 파일 이름을 적으므로, `sections/Problems.tex`는 이름이 같은 다른
    // 파일이다. `\input` 파일의 줄 번호는 여기서 뜻이 없다.
    func isHere(_ issue: TexIssue) -> Bool {
        guard let file = issue.file, issue.line != nil else { return false }
        let relative = file.hasPrefix("./") ? String(file.dropFirst(2)) : file
        return relative == name || URL(filePath: file).standardizedFileURL == fileURL.standardizedFileURL
    }

    func jump(to issue: TexIssue) {
        guard isHere(issue), let line = issue.line else { return }
        reveal = line
    }

    func label(_ issue: TexIssue) -> String {
        guard let line = issue.line else { return issue.message }
        let place = isHere(issue) ? String(localized: .textFileLine(line)) : "\(issue.file ?? ""):\(line)"
        return "\(place) · \(issue.message)"
    }
}
