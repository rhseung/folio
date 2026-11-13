import FolioLint
import Testing

private func found(_ files: [String: String], _ check: String) -> [String] {
    let code = Codebase(files: files)
    return Rules.all.filter { $0.name == check }.flatMap { $0.hits(in: code) }.map(\.key).sorted()
}

private let view = "app/features/demo/demo-view.swift"

@Suite struct ViewWorkspaceCallTests {
    @Test func callsOnTheWorkspaceInAView() {
        let source = """
            struct DemoView: View {
                var body: some View {
                    Button(.commonSave) { workspace.run(.save) }
                    CourseDot(color: model.workspace.accent(id).color)
                }
            }
            """
        #expect(found([view: source], "view-workspace-call") == ["workspace.accent(", "workspace.run("])
    }

    @Test func anExtensionInAnotherFileIsTheSameView() {
        let files = [
            view: "struct DemoView: View { var body: some View { row } }",
            "app/features/demo/demo-rows.swift": "extension DemoView { var row: some View { Text(workspace.title()) } }",
        ]
        #expect(found(files, "view-workspace-call") == ["workspace.title("])
    }

    @Test func readsAndModelsAndProseDoNotCount() {
        let files = [
            view: """
                struct DemoView: View {
                    // workspace.run(.save) once lived here
                    var body: some View { Text("workspace.run(").id(workspace.notesRevision) }
                }
                """,
            "app/features/demo/demo-model.swift": "final class DemoModel { func save() { workspace.run(.save) } }",
        ]
        #expect(found(files, "view-workspace-call").isEmpty)
    }
}

@Suite struct ViewBodyLogicTests {
    @Test func sortingFilteringAndCountingInViewMembers() {
        let source = """
            struct DemoView: View {
                var body: some View {
                    ForEach(items.filter { $0.done }.sorted(by: <)) { Text($0.title) }
                    Text(String(items.count(where: \\.done)))
                }
                @ViewBuilder func groups() -> some View {
                    ForEach(Dictionary(grouping: items, by: \\.week).keys) { Text($0) }
                    Text(items.max(by: { $0.size < $1.size })?.title ?? "")
                }
            }
            """
        #expect(found([view: source], "view-body-logic") == [
            "body: .count(where", "body: .filter", "body: .sorted", "groups: .max(by", "groups: Dictionary(grouping",
        ])
    }

    @Test func propertiesAndNonViewMembersDoNotCount() {
        let source = """
            struct DemoView: View {
                var body: some View { Text(String(items.count)).frame(minWidth: items.min()) }
                var visible: [Item] { items.filter(\\.shown) }
            }
            """
        #expect(found([view: source], "view-body-logic").isEmpty)
    }
}

@Suite struct UIStringTests {
    @Test func koreanAnywhereAndEnglishWhereSwiftUIShowsIt() {
        let source = """
            struct DemoView: View {
                var body: some View {
                    Text("완료")
                    Button("Save") {}
                    Text("\\(count) items").help("Open the file")
                    Text(verbatim: "ok").id("row-key")
                }
            }
            """
        #expect(found(["app/features/demo/demo-view.swift": source], "ui-string")
            == ["\" items\"", "\"Open the file\"", "\"Save\"", "\"완료\""])
    }

    @Test func dataMarksDebugCodeAndPreviewsAreLeftOut() {
        let source = """
            let fillers = [ // strings: data, matched against transcripts
                "음",
                "어",
            ]
            let title = "Claude 답변" // strings: data, written into the note file
            #if DEBUG
            let sample = "가나다"
            #else
            let shipped = "라마바"
            #endif
            #Preview { Text("미리보기") }
            """
        #expect(found(["app/features/demo/demo.swift": source], "ui-string") == ["\"라마바\""])
        #expect(found(["app/app/debug-demo.swift": "let a = \"가\""], "ui-string").isEmpty)
    }
}

@Suite struct LayoutNameTests {
    @Test func standardNamesOutsideStandardLayout() {
        let files = [
            "packages/folio-core/sources/folio-storage/store.swift": "let notes = \"Notes\"; let path = \"Notes/assets\"",
            "packages/folio-core/sources/folio-domain/layout/standard-layout.swift": "let notes = \"Notes\"",
            "packages/folio-core/sources/folio-fixtures/standard.swift": "let notes = \"Notes\"",
        ]
        #expect(found(files, "layout-name") == ["\"Notes\""])
    }
}

@Suite struct LayerTests {
    @Test func uiInPackagesAndDiskInTheDomain() {
        let files = [
            "packages/folio-ai/sources/folio-ai/panel.swift": "import SwiftUI",
            "packages/folio-core/sources/folio-domain/rule.swift": """
                let manager = FileManager.default
                let data = try Data(contentsOf: url)
                try text.write(to: url, atomically: true, encoding: .utf8)
                """,
            "packages/folio-core/sources/folio-storage/store.swift": "let manager = FileManager.default",
        ]
        #expect(found(files, "layer") == [
            "disk: .write(to:", "disk: Data(contentsOf:", "disk: FileManager", "disk: atomically:", "import SwiftUI",
        ])
    }

    @Test func fileManagerInScreensButNotInDebugCode() {
        let files = [
            "app/features/demo/demo-model.swift": "let manager = FileManager.default",
            "app/features/demo/demo-walk.swift": "#if DEBUG\nlet manager = FileManager.default\n#endif",
        ]
        #expect(found(files, "layer") == ["FileManager in a screen"])
    }
}

@Suite struct RestatingCommentTests {
    @Test func aLoneLineThatOnlyNamesTheDeclaration() {
        let source = """
            struct Course {
                /// The course title.
                var courseTitle: String

                /// Shown above the fold, so it stays one line.
                var subtitle: String

                // The course's code,
                // as the registrar writes it.
                var code: String

                /// 과목 이름.
                var name: String
            }
            enum Token {
                /// `[[` opens a link.
                case linkOpen
            }
            """
        #expect(found(["app/features/demo/course.swift": source], "restating-comment") == ["The course title."])
    }

    @Test func actionFieldsAreCLIHelp() {
        let source = "struct AddNote { /// The note title.\n var noteTitle: String }"
        #expect(found(["packages/folio-core/sources/folio-actions/note.swift": source], "restating-comment").isEmpty)
    }
}

@Suite struct BaselineTests {
    @Test func newPlacesAndGonePlaces() {
        let code = Codebase(files: ["app/features/demo/demo.swift": "let a = \"가\"\nlet b = \"가\"\nlet c = \"나\""])
        let hits = Rules.all.filter { $0.name == "ui-string" }.flatMap { $0.hits(in: code) }
        let report = Baseline.compare(hits, with: Baseline.entries(in: """
            # header
            ui-string\tapp/features/demo/demo.swift\t"가"
            ui-string\tapp/features/demo/demo.swift\t"다"
            """))
        #expect(report.new.map { "\($0.line) \($0.key)" } == ["2 \"가\"", "3 \"나\""])
        #expect(report.gone == ["ui-string\tapp/features/demo/demo.swift\t\"다\""])
        #expect(Baseline.compare(hits, with: Baseline.entries(in: Baseline.render(hits))).passed)
    }
}
