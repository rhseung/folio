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
            found(["app/features/demo/demo-view.swift": source], "ui-string")
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
        #expect(found(["app/window/debug-demo.swift": "let a = \"가\""], "ui-string").isEmpty)
        #expect(found(["app/window/debug/scenario-menu.swift": "let a = \"가\""], "ui-string").isEmpty)
    }
}

@Suite struct LayoutNameTests {
    @Test func standardNamesOutsideStandardLayout() {
        let files = [
            "sources/storage/store.swift": "let notes = \"Notes\"; let path = \"Notes/assets\"",
            "sources/domain/folder/standard-layout.swift": "let notes = \"Notes\"",
            "sources/domain/folder/course-folder.swift": "let notes = \"Notes\"",
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
        #expect(found(["sources/actions/note.swift": source], "restating-comment").isEmpty)
    }
}

@Suite struct DocCommentTests {
    @Test func onlyActionFieldsKeepDocComments() {
        let source = """
            /// Adds a note.
            @Action("note add", "노트 만들기", done: "{title}")
            struct AddNote {
                /// The note's title.
                @Arg var title: String
                /// Where it goes.
                var folder: String?
                // A plain comment stays.
                var hidden: Bool
                /** A block. */
                func perform() {}
                struct Inner {
                    /// Not a field of the action.
                    var name: String
                }
            }
            struct Plain {
                /// Due today.
                var due: Date
                var name: String /// trailing
            }
            """
        #expect(
            found(["sources/actions/note.swift": source], "doc-comment") == [
                "/** A block. */", "/// Adds a note.", "/// Due today.", "/// Not a field of the action.", "/// trailing",
            ])
    }

    @Test func queryFieldsKeepDocComments() {
        let source = """
            @Query("exam show", "시험 보기")
            struct ExamShow {
                /// 시험
                @Arg var exam: Exam.ID
            }
            """
        #expect(found(["sources/actions/exams/exam-show.swift": source], "doc-comment").isEmpty)
    }

    @Test func codeInStringsIsNotAComment() {
        let source = "let example = \"/// a doc comment\"\nlet block = \"\"\"\n    /// inside\n    \"\"\"\n"
        #expect(found(["tests/unit/macros/action-tests.swift": source], "doc-comment").isEmpty)
    }

    @Test func linesPointAtTheComment() {
        let code = Codebase(files: ["app/a.swift": "let a = 1\n\n/// Two.\n/// Lines.\nlet b = 2"])
        let lines = Rules.all.filter { $0.name == "doc-comment" }.flatMap { $0.hits(in: code) }.map(\.line)
        #expect(lines == [3, 4])
    }
}

@Suite struct BaselineTests {
    @Test func newPlacesAndGonePlaces() {
        let code = Codebase(files: ["app/features/demo/demo.swift": "let a = \"가\"\nlet b = \"가\"\nlet c = \"나\""])
        let hits = Rules.all.filter { $0.name == "ui-string" }.flatMap { $0.hits(in: code) }
        let report = Baseline.compare(
            hits,
            with: Baseline.entries(
                in: """
                    # header
                    ui-string\tapp/features/demo/demo.swift\t"가"
                    ui-string\tapp/features/demo/demo.swift\t"다"
                    """))
        #expect(report.new.map { "\($0.line) \($0.key)" } == ["2 \"가\"", "3 \"나\""])
        #expect(report.gone == ["ui-string\tapp/features/demo/demo.swift\t\"다\""])
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
        #expect(found(["app/design/tokens/theme.swift": "let tone = Color.red"], "design-value").isEmpty)
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

@Suite struct DesignTokenTests {
    @Test func opacityNumbersInScreens() {
        let source = """
            struct DemoView: View {
                var body: some View {
                    Text(.commonSave).opacity(0.4).opacity(on ? 1 : 0.6).opacity(0).opacity(1)
                    Rectangle().fill(Color.black.opacity(Theme.Opacity.tint)).opacity(max(0.15, level))
                    Rectangle().opacity((on ? 1 : Theme.Opacity.faded) * 0.5)
                    Text(.commonSave).opacity(0.3) // design: one-off, a window drawn small
                }
            }
            """
        #expect(found([view: source], "design-opacity") == ["opacity(0.15)", "opacity(0.4)", "opacity(0.6)"])
        #expect(found(["app/design/meter.swift": "let a = Color.black.opacity(0.4)"], "design-opacity").isEmpty)
    }

    @Test func shadowValuesEverywhereButTheTheme() {
        let source = """
            struct DemoView: View {
                var body: some View {
                    Text(.commonSave).shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                    Text(.commonSave).shadow(Theme.Shadow.floating).shadow(Theme.Shadow.lifted, shown: hovering)
                }
            }
            """
        #expect(found([view: source], "design-shadow") == ["shadow(radius: 24)"])
        #expect(found(["app/design/knob.swift": "let k = Circle().shadow(radius: 2)"], "design-shadow") == ["shadow(radius: 2)"])
        let theme = "func shadow(_ s: Theme.Shadow) -> some View { shadow(color: .black, radius: s.radius) }"
        #expect(found(["app/design/tokens/theme.swift": theme], "design-shadow").isEmpty)
    }

    @Test func curvesWithTheirOwnDuration() {
        let source = """
            struct DemoView: View {
                static let spring = Animation.spring(duration: 0.32, bounce: 0.35)
                var body: some View {
                    Text(.commonSave)
                        .animation(.easeOut(duration: 0.25), value: done)
                        .animation(Theme.Motion.quick, value: done)
                        .animation(.snappy, value: done)
                    Button(.commonSave) { withAnimation(.snappy(duration: 0.45)) { advance() } }
                }
            }
            """
        #expect(
            found([view: source], "design-motion") == [
                ".easeOut(duration: 0.25)", ".snappy(duration: 0.45)", ".spring(duration: 0.32, bounce: 0.35)",
            ])
        #expect(
            found(["app/design/tokens/theme.swift": "static let quick = Animation.snappy(duration: 0.2)"], "design-motion").isEmpty)
    }

    @Test func frameAndPillNumbersInScreens() {
        let source = """
            struct DemoView: View {
                var body: some View {
                    Text(.commonSave).frame(width: 84, alignment: .leading).frame(minWidth: 720, idealWidth: wide ? 960 : 1280)
                    TextField("", text: $score).pill(width: 72)
                    Divider().frame(height: 1).frame(width: 0)
                    Rectangle().frame(width: reach * 2, height: max(4, level)).frame(maxWidth: .infinity)
                    TextField("", text: $code).pill(width: Theme.Size.numberField).frame(width: Theme.Size.dateColumn)
                    Text(.commonSave).frame(width: 14) // design: one-off, the system slider knob
                }
            }
            #Preview { DemoView().frame(width: 1440, height: 900) }
            """
        #expect(
            found([view: source], "design-size") == [
                "frame(height: 4)", "frame(idealWidth: 1280)", "frame(idealWidth: 960)", "frame(minWidth: 720)", "frame(width: 84)",
                "pill(width: 72)",
            ])
        let debug = "struct Probe: View { var body: some View { Color.clear.frame(width: 1180, height: 720) } }"
        #expect(found(["app/window/debug/form-snapshots.swift": debug], "design-size").isEmpty)
    }
}

@Suite struct CourseAccentTests {
    @Test func theAccentAloneOutsideTheDesignFolder() {
        let line = "Text(.commonSave).environment(\\.accent, accent).environment(\\.locale, locale)"
        #expect(found(["app/features/demo/demo-view.swift": line], "course-accent") == ["environment(\\.accent"])
        #expect(
            found(["app/design/tokens/course-accent.swift": line, "tests/unit/app/note-bench.swift": line], "course-accent").isEmpty
        )
    }
}

@Suite struct LocalFoldersTests {
    @Test func applicationSupportOutsideLocalFolders() {
        let files = [
            "app/features/demo/demo-model.swift": "let folder = URL.applicationSupportDirectory",
            "tests/unit/app/demo-tests.swift": "let folder = home + \"/Library/Application Support/Folio\"",
            "sources/ai/cache.swift": "let paths = NSSearchPathForDirectoriesInDomains(.a, .b, true)",
            "app/workspace/services/local-folders.swift": "let folder = URL.applicationSupportDirectory",
            "app/features/demo/demo-note.swift": "// not URL.applicationSupportDirectory",
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
            "app/features/course/note-embed.swift": "struct NoteEmbedSource {}\nfinal class CourseModel {}",
            "app/features/settings/settings-model.swift": "final class SettingsModel {}",
            "app/features/first-run/first-run-model.swift": "let settings = SettingsModel(); let embed = NoteEmbedSource()",
            "app/platform/note-preview.swift": "let source: NoteEmbedSource",
            "app/features/course/course-view.swift": "let model: CourseModel",
            "app/design/tokens/theme.swift": "struct Theme {}",
            "app/features/today/today-view.swift": "let theme = Theme()",
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
            "app/window/screen.swift": """
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
        #expect(found(["app/window/window.swift": source], "screen-toolbar").isEmpty)
    }
}

@Suite struct LaunchEnvironmentTests {
    @Test func theEnvironmentOutsideTheLaunchFiles() {
        let read = "let env = ProcessInfo.processInfo.environment"
        let files = [
            "app/platform/pdf-view.swift": read,
            "app/workspace/workspace.swift": read,
            "app/window/debug/debug-snapshots.swift": read,
            "tests/unit/app/render-tests.swift": read,
            "tests/unit/cli/env.swift": read,
            "app/features/demo/demo-model.swift": "#if DEBUG\n\(read)\n#endif",
        ]
        #expect(found(files, "launch-environment") == ["ProcessInfo.processInfo.environment"])
    }
}

@Suite struct NameAndFolderTests {
    @Test func kebabCaseNames() {
        let files = [
            "app/features/demo/demo-view.swift": "", "app/features/Demo/DemoModel.swift": "",
            "Package.swift": "", "app/features/demo/grade_math.swift": "",
        ]
        #expect(found(files, "kebab-names") == ["Demo", "DemoModel", "grade_math"])
    }

    @Test func foldersPastTwentyFiles() {
        var files: [String: String] = [:]
        for index in 1...21 { files["app/window/file-\(index).swift"] = "" }
        for index in 1...20 { files["app/design/file-\(index).swift"] = "" }
        let hits = Rules.all.filter { $0.name == "folder-size" }.flatMap { $0.hits(in: Codebase(files: files)) }
        #expect(hits.map(\.path) == ["app/window"])
    }
}

@Suite struct DesignControlTests {
    @Test func systemControlsInAFeature() {
        let source = """
            struct DemoView: View {
                var body: some View {
                    Toggle("", isOn: $on)
                    Picker("", selection: $pick) { Text("a") }
                    TextField("", text: $name)
                    Button(.commonSave) {}.buttonStyle(.borderless)
                    Button(.commonSave) {}.buttonStyle(PlainButtonStyle())
                }
            }
            """
        #expect(
            found([view: source], "design-control") == [
                ".buttonStyle(.borderless)", ".buttonStyle(PlainButtonStyle())", "Picker(", "TextField(", "Toggle(",
            ])
    }

    @Test func atomsMenuContentAndDesignPass() {
        let source = """
            struct DemoView: View {
                var body: some View {
                    TextField("", text: $code).pill(width: Theme.Size.codeField)
                    Button(.commonSave) {}.buttonStyle(.pointing(.plain))
                    Button(.commonSave) {}.buttonStyle(.ghost)
                    Menu {
                        Toggle("", isOn: $on)
                    } label: {
                        ChipLabel("")
                    }
                    Text("").contextMenu { Picker("", selection: $pick) { Text("a") } }
                }
            }
            """
        #expect(found([view: source], "design-control").isEmpty)
        #expect(
            found(
                ["app/design/atoms/fields/switch.swift": "struct Switch: View { var body: some View { Toggle(\"\", isOn: $on) } }"],
                "design-control"
            ).isEmpty)
    }

    @Test func aControlThatOpensAContextMenuStillCounts() {
        let source = "struct DemoView: View { var body: some View { TextField(\"\", text: $name).contextMenu { Text(\"\") } } }"
        #expect(found([view: source], "design-control") == ["TextField("])
    }

    @Test func aButtonStyleDeclaredInAFeature() {
        let source =
            "private struct SoftStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label } }"
        #expect(found([view: source], "design-control") == ["ButtonStyle SoftStyle"])
    }
}

@Suite struct FileNameTextTests {
    @Test func aFileNameDrawnWithText() {
        let source = """
            struct DemoView: View {
                var body: some View {
                    Text((m.path as NSString).lastPathComponent).lineLimit(1)
                    Text(url.lastPathComponent)
                }
            }
            """
        #expect(found([view: source], "file-name") == ["Text((m.path as NSString).lastPathComponent)", "Text(url.lastPathComponent)"])
    }

    @Test func fileNameAndWrappingDescriptionsPass() {
        let source = """
            struct DemoView: View {
                var body: some View {
                    FileName(url.lastPathComponent)
                    ContentUnavailableView("", systemImage: "photo", description: Text(url.lastPathComponent))
                    Text(.materialsLinksTitle(url.lastPathComponent))
                }
            }
            """
        #expect(found([view: source], "file-name").isEmpty)
    }
}
