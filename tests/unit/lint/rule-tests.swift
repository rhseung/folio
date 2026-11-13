import FolioLint
import Testing

private func found(_ files: [String: String], _ check: String) -> [String] {
    let code = Codebase(files: files)
    return Rules.all.filter { $0.name == check }.flatMap { $0.hits(in: code) }.map(\.key).sorted()
}

private let view = "sources/app/features/demo/demo-view.swift"

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
            "sources/app/features/demo/demo-rows.swift": "extension DemoView { var row: some View { Text(workspace.title()) } }",
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
            "sources/app/features/demo/demo-model.swift": "final class DemoModel { func save() { workspace.run(.save) } }",
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
        #expect(
            found([view: source], "view-body-logic") == [
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
        #expect(
            found(["sources/app/features/demo/demo-view.swift": source], "ui-string")
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
        #expect(found(["sources/app/features/demo/demo.swift": source], "ui-string") == ["\"라마바\""])
        #expect(found(["sources/app/app/debug-demo.swift": "let a = \"가\""], "ui-string").isEmpty)
    }
}

@Suite struct LayoutNameTests {
    @Test func standardNamesOutsideStandardLayout() {
        let files = [
            "sources/storage/store.swift": "let notes = \"Notes\"; let path = \"Notes/assets\"",
            "sources/domain/layout/standard-layout.swift": "let notes = \"Notes\"",
            "sources/fixtures/standard.swift": "let notes = \"Notes\"",
        ]
        #expect(found(files, "layout-name") == ["\"Notes\""])
    }
}

@Suite struct LayerTests {
    @Test func uiInPackagesAndDiskInTheDomain() {
        let files = [
            "sources/ai/panel.swift": "import SwiftUI",
            "sources/domain/rule.swift": """
            let manager = FileManager.default
            let data = try Data(contentsOf: url)
            try text.write(to: url, atomically: true, encoding: .utf8)
            """,
            "sources/storage/store.swift": "let manager = FileManager.default",
        ]
        #expect(
            found(files, "layer") == [
                "disk: .write(to:", "disk: Data(contentsOf:", "disk: FileManager", "disk: atomically:", "import SwiftUI",
            ])
    }

    @Test func fileManagerInScreensButNotInDebugCode() {
        let files = [
            "sources/app/features/demo/demo-model.swift": "let manager = FileManager.default",
            "sources/app/features/demo/demo-walk.swift": "#if DEBUG\nlet manager = FileManager.default\n#endif",
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
        #expect(found(["sources/app/features/demo/course.swift": source], "restating-comment") == ["The course title."])
    }

    @Test func actionFieldsAreCLIHelp() {
        let source = "struct AddNote { /// The note title.\n var noteTitle: String }"
        #expect(found(["sources/actions/note.swift": source], "restating-comment").isEmpty)
    }
}

@Suite struct BaselineTests {
    @Test func newPlacesAndGonePlaces() {
        let code = Codebase(files: ["sources/app/features/demo/demo.swift": "let a = \"가\"\nlet b = \"가\"\nlet c = \"나\""])
        let hits = Rules.all.filter { $0.name == "ui-string" }.flatMap { $0.hits(in: code) }
        let report = Baseline.compare(
            hits,
            with: Baseline.entries(
                in: """
                    # header
                    ui-string\tsources/app/features/demo/demo.swift\t"가"
                    ui-string\tsources/app/features/demo/demo.swift\t"다"
                    """))
        #expect(report.new.map { "\($0.line) \($0.key)" } == ["2 \"가\"", "3 \"나\""])
        #expect(report.gone == ["ui-string\tsources/app/features/demo/demo.swift\t\"다\""])
        #expect(Baseline.compare(hits, with: Baseline.entries(in: Baseline.render(hits))).passed)
    }
}

@Suite struct DesignValueTests {
    @Test func rawSizesColoursAndRadiiInScreens() {
        let source = """
            struct DemoView: View {
                var body: some View {
                    Text(.commonSave).font(.system(size: 13)).foregroundStyle(.red)
                    RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.2))
                    Rectangle().fill(Color(red: 0.2, green: 0.3, blue: 0.4)).tint(isOn ? .green : .gray)
                    Text(.commonSave).shadow(color: .black, radius: 4).shadow(color: .black.opacity(0.1), radius: 2)
                    Text(.commonSave).font(.system(size: 40)) // design: one-off, the timer's digits
                    // .foregroundStyle(.red) once lived here
                    Text(verbatim: ".red")
                }
                let tone = 0xFF8800
            }
            """
        #expect(
            found([view: source], "design-value") == [
                ".gray", ".green", ".red", ".system(size:", "0xFF8800", "Color(red:", "Color.blue", "cornerRadius: 8",
            ])
        #expect(found(["sources/app/design/theme.swift": "let tone = Color.red"], "design-value").isEmpty)
    }
}

@Suite struct DesignGridTests {
    @Test func oddAndFractionalSpacingSizesAndRadii() {
        let source = """
            struct DemoView: View {
                let gap: CGFloat = 6
                let room: CGFloat = 7
                var body: some View {
                    VStack(spacing: 3) {
                        Text(.commonSave).padding(5).padding(.horizontal, 2.5).padding(.top, 8)
                        Rectangle().frame(width: 1, height: 12).offset(x: 3)
                        CourseDot(color: .accentColor, size: 9)
                        Divider().frame(height: 1).padding(.leading, -3)
                        Text(.commonSave).frame(width: 17) // design: one-off, the column of digits
                    }
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(lineWidth: 1.5))
                }
            }
            """
        #expect(
            found([view: source], "design-grid") == [
                "CGFloat = 7", "padding(-3)", "padding(2.5)", "padding(5)", "size: 9", "spacing: 3",
            ])
    }
}

@Suite struct CourseAccentTests {
    @Test func theAccentAloneOutsideTheDesignFolder() {
        let line = "Text(.commonSave).environment(\\.accent, accent).environment(\\.locale, locale)"
        #expect(found(["sources/app/features/demo/demo-view.swift": line], "course-accent") == ["environment(\\.accent"])
        #expect(found(["sources/app/design/course-accent.swift": line, "tests/unit/app/note-bench.swift": line], "course-accent").isEmpty)
    }
}

@Suite struct LocalFoldersTests {
    @Test func applicationSupportOutsideLocalFolders() {
        let files = [
            "sources/app/features/demo/demo-model.swift": "let folder = URL.applicationSupportDirectory",
            "tests/unit/app/demo-tests.swift": "let folder = home + \"/Library/Application Support/Folio\"",
            "sources/ai/cache.swift": "let paths = NSSearchPathForDirectoriesInDomains(.a, .b, true)",
            "sources/app/app/services/local-folders.swift": "let folder = URL.applicationSupportDirectory",
            "sources/app/features/demo/demo-note.swift": "// not URL.applicationSupportDirectory",
        ]
        #expect(
            found(files, "local-folders") == [
                "\"Library/Application Support\"", "NSSearchPathForDirectoriesInDomains", "applicationSupportDirectory",
            ])
    }
}

@Suite struct AppDirectionTests {
    @Test func lowerLayersAndOtherFeaturesModels() {
        let files = [
            "sources/app/features/course/note-embed.swift": "struct NoteEmbedSource {}\nfinal class CourseModel {}",
            "sources/app/features/settings/settings-model.swift": "final class SettingsModel {}",
            "sources/app/features/first-run/first-run-model.swift": "let settings = SettingsModel(); let embed = NoteEmbedSource()",
            "sources/app/platform/note-preview.swift": "let source: NoteEmbedSource",
            "sources/app/features/course/course-view.swift": "let model: CourseModel",
            "sources/app/design/theme.swift": "struct Theme {}",
            "sources/app/features/today/today-view.swift": "let theme = Theme()",
        ]
        #expect(found(files, "app-direction") == ["NoteEmbedSource from features/course", "SettingsModel from features/settings"])
    }
}

@Suite struct KindDefaultTests {
    @Test func aDefaultInASwitchOverAppLinkKinds() {
        let files = [
            "sources/domain/app-link.swift": """
            struct AppLink { enum Kind: String { case today, note, material } }
            """,
            "sources/app/app/screen.swift": """
            func screen(_ link: AppLink) {
                switch link.kind {
                case .note: break
                default: break
                }
                switch link.kind {
                case .today, .note, .material: break
                }
                switch item.kind {
                case .note, .heading: break
                default: break
                }
            }
            """,
        ]
        #expect(found(files, "kind-default") == ["switch link.kind default:"])
    }
}

@Suite struct MinuteTimelineTests {
    @Test func slowSchedulesButNotSecondTimers() {
        let source = """
            TimelineView(.everyMinute) { _ in row }
            TimelineView(.periodic(from: start, by: 86_400)) { _ in page }
            TimelineView(.periodic(from: start, by: 1)) { _ in timer }
            TimelineView(.animation) { _ in glide }
            """
        #expect(found([view: source], "minute-timeline") == ["TimelineView(.everyMinute)", "TimelineView(.periodic)"])
    }
}

@Suite struct ScreenToolbarTests {
    @Test func theWindowToolbarFromAScreen() {
        let source = "Text(.commonSave).toolbar { Button(.commonClose) {} }.buttonStyle(.toolbar).toolbarGroup()"
        #expect(found([view: source], "screen-toolbar") == [".toolbar"])
        #expect(found(["sources/app/app/window.swift": source], "screen-toolbar").isEmpty)
    }
}

@Suite struct LaunchEnvironmentTests {
    @Test func theEnvironmentOutsideTheLaunchFiles() {
        let read = "let env = ProcessInfo.processInfo.environment"
        let files = [
            "sources/app/platform/pdf-view.swift": read,
            "sources/app/app/workspace/workspace.swift": read,
            "sources/app/app/debug/debug-snapshots.swift": read,
            "tests/unit/app/render-tests.swift": read,
            "tests/unit/cli/env.swift": read,
            "sources/app/features/demo/demo-model.swift": "#if DEBUG\n\(read)\n#endif",
        ]
        #expect(found(files, "launch-environment") == ["ProcessInfo.processInfo.environment"])
    }
}

@Suite struct NameAndFolderTests {
    @Test func kebabCaseNames() {
        let files = [
            "sources/app/features/demo/demo-view.swift": "", "sources/app/features/Demo/DemoModel.swift": "",
            "Package.swift": "", "sources/app/features/demo/grade_math.swift": "",
        ]
        #expect(found(files, "kebab-names") == ["Demo", "DemoModel", "grade_math"])
    }

    @Test func foldersPastTwentyFiles() {
        var files: [String: String] = [:]
        for index in 1...21 { files["sources/app/app/file-\(index).swift"] = "" }
        for index in 1...20 { files["sources/app/design/file-\(index).swift"] = "" }
        let hits = Rules.all.filter { $0.name == "folder-size" }.flatMap { $0.hits(in: Codebase(files: files)) }
        #expect(hits.map(\.path) == ["sources/app/app"])
    }
}
