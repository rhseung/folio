import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import Folio

@MainActor
struct NewMaterialFileModelTests {
    let workspace: Workspace
    let course: LoadedCourse

    init() throws {
        workspace = try fixtureWorkspace()
        workspace.run(MaterialTrack(course: graphTheory))
        course = try #require(workspace.course(graphTheory))
    }

    @Test func startsInTheFolderOfTheAssignmentDueLast() throws {
        workspace.run(AssignmentAdd(course: graphTheory, title: "HW 4", due: workspace.now.addingTimeInterval(86_400)))
        let model = NewMaterialFileModel(workspace: workspace, course: try #require(workspace.course(graphTheory)), folder: nil)
        #expect(model.places.prefix(2) == ["Study", "Archive"])
        #expect(model.places.contains("Assignments/SP01"))
        #expect(model.folder == "Assignments/HW04")
    }

    @Test func aNameWithoutAnExtensionIsATex() {
        let model = NewMaterialFileModel(workspace: workspace, course: course, folder: "Assignments/HW03")
        #expect(!model.canCreate && model.refusal == nil)
        model.name = " hw3 "
        #expect(model.fileName == "hw3.tex")
        model.name = "풀이.py"
        #expect(model.fileName == "풀이.py")
    }

    @Test func createsAndOpensTheFileInTheEditor() throws {
        let materials = MaterialsModel(workspace: workspace, course: course)
        materials.startNewFile(in: "Assignments/HW03")
        let model = NewMaterialFileModel(workspace: workspace, course: course, folder: materials.newFileFolder)
        model.name = "hw3"
        #expect(model.canCreate)
        let id = try #require(model.create())
        materials.created(id)
        #expect(materials.viewed?.path == "Assignments/HW03/hw3.tex")
        #expect(materials.viewed?.isText == true)
        #expect(materials.opened.isSuperset(of: ["Assignments", "Assignments/HW03"]))
        #expect(try course.store.readText("Assignments/HW03/hw3.tex").hasPrefix("\\documentclass"))
    }

    @Test func aTakenNameIsRefusedBeforeCreating() throws {
        try course.store.writeText("Study/a.txt", text: "원래")
        let model = NewMaterialFileModel(workspace: workspace, course: course, folder: "Study")
        model.name = "a.txt"
        #expect(!model.canCreate)
        #expect(model.refusal == "같은 이름의 파일이 이미 있습니다: Study/a.txt")
        model.name = "a.pdf"
        #expect(model.refusal?.hasPrefix("Folio에서 편집하는 형식") == true)
    }

    @Test func aSubfolderIsKept() {
        let model = NewMaterialFileModel(workspace: workspace, course: course, folder: "Study/풀이")
        #expect(model.folder == "Study/풀이" && model.places.contains("Study/풀이"))
    }

    @Test func onlyOwnFoldersOfferNewFiles() throws {
        let materials = MaterialsModel(workspace: workspace, course: course)
        let folders = materials.sections().flatMap(\.rows).compactMap { row -> PathTree<FolioDomain.Material>? in
            if case .folder(let f, _) = row { f } else { nil }
        }
        let hw = try #require(folders.first { $0.path == "Assignments/HW03" })
        #expect(materials.acceptsNewFile(hw))
        for f in folders where f.path.hasPrefix("Lectures") || f.path.hasPrefix("Inherited") { #expect(!materials.acceptsNewFile(f)) }
    }
}
