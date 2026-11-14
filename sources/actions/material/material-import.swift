import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material import", "바깥 파일을 과목 폴더로 복사해 등록하고 회차에 연결", effect: .creates, done: "파일 {items}을(를) 가져왔습니다",
    phrases: ["파일 가져오기", "다운로드한 자료 넣기", "외부 파일 복사"], cli: .manual(reason: "파일마다 --folder와 --session을 붙여 가져올 항목(ImportItem)을 만든다"))
public struct MaterialImport {
    @Arg var course: Course.ID
    var items: [ImportItem]

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        for item in items {
            guard store.contains(item.folder) else { throw ActionError.rule(String(localized: .errorMaterialImportOutside(item.folder))) }
            guard FileManager.default.fileExists(atPath: item.file) else {
                throw ActionError.notFound(String(localized: .errorMaterialImportMissing(item.file)))
            }
            if let session = item.session { _ = try index(session, in: file.sessions, .valueSession) }
            if let cuts = item.sections { try checkCuts(cuts, in: file) }
        }

        var linked: [(path: String, item: ImportItem)] = []
        for item in items {
            let url = URL(filePath: item.file)
            if let inside = store.coursePath(of: url) {
                linked.append((inside, item))
                continue
            }
            let name = MaterialIntake.name(url.lastPathComponent, in: item.folder, session: file.sessions.first { $0.id == item.session })
            let planned = try ctx.relative(course, "\(item.folder)/\(name)")
            if let path = try ctx.io(Change(.added, planned), { try store.importFile(url, into: item.folder, name: name) }) {
                linked.append((path, item))
            }
        }

        try ctx.edit(course) { f in
            try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now)
            for (path, item) in linked {
                guard let m = f.materials.first(where: { $0.path == path }) else { continue }
                if let session = item.session { f.linkMaterial(m.id, session: session) }
                if let cuts = item.sections { f.split(m.id, into: cuts, device: ctx.device, now: ctx.now) }
            }
        }
    }
}
