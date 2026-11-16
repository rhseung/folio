import FolioLint
import Testing

private func found(_ paths: [String], _ check: String) -> [String] {
    let code = Codebase(files: Dictionary(uniqueKeysWithValues: paths.map { ($0, "") }))
    return Rules.all.filter { $0.name == check }.flatMap { $0.hits(in: code) }.map(\.path).sorted()
}

@Suite struct FolderSmallTests {
    @Test func oneFileOrTwoWithoutAnAreaName() {
        let paths = [
            "app/design/atoms/layout/layout.swift", "app/design/atoms/layout/flow-layout.swift",
            "app/design/atoms/buttons/ghost-button.swift",
            "app/design/tokens/notes/note-look.swift", "app/design/tokens/notes/note-style.swift", "app/design/tokens/theme.swift",
            "sources/markdown/syntax/note-syntax.swift",
        ]
        #expect(
            found(paths, "folder-small") == [
                "app/design/atoms/buttons", "app/design/atoms/layout", "sources/markdown/syntax",
            ])
    }

    @Test func aFolderWeighsItsSubfoldersToo() {
        let paths = ["app/window/tabs/tab-bar.swift", "app/window/tabs/tab-row.swift", "app/window/tabs/tab-strip.swift"]
        #expect(found(paths, "folder-small").isEmpty)
    }

    @Test func anAreaFolderOfAnAreaLayerMayBeSmall() {
        let paths = [
            "sources/actions/claude/proposal-list.swift", "sources/actions/notes/note-add.swift",
            "sources/actions/notes/note-mv.swift", "sources/actions/notes/note-rm.swift",
            "sources/actions/notes/figure/note-figure-add.swift",
        ]
        #expect(found(paths, "folder-small") == ["sources/actions/notes/figure"])
    }

    @Test func aTestFolderShapedLikeItsSourceMayBeSmall() {
        let paths = [
            "sources/domain/import/quick-add/quick-add.swift", "sources/domain/import/quick-add/quick-add-line.swift",
            "sources/domain/import/quick-add/quick-add-date.swift",
            "tests/unit/domain/import/quick-add/quick-add-corpus-tests.swift",
            "tests/unit/domain/import/stray/stray-tests.swift",
        ]
        #expect(found(paths, "folder-small") == ["tests/unit/domain/import/stray"])
    }

    @Test func moduleAndGeneratedFoldersMayBeSmall() {
        let paths = [
            "sources/index/search-index.swift", "sources/tools/folio/main.swift", "tests/unit/index/index-tests.swift",
            "tests/unit/tools/dev/version-tests.swift", "tests/e2e/app/a11y-tests.swift",
            "sources/cli/render/generated/note-theme.swift", "sources/cli/render/page-render.swift",
            "sources/cli/render/render-result.swift", "sources/cli/render/widgets/widget-render.swift",
        ]
        #expect(found(paths, "folder-small") == ["sources/cli/render/widgets"])
    }
}

@Suite struct FolderNameTests {
    @Test func heavyNamesRepeatedParentsAndRoleFolders() {
        let paths = [
            "sources/actions/core/action.swift", "sources/domain/window/shared/menu.swift",
            "sources/domain/sessions/sessions/session.swift", "app/window/window-tabs/tab-bar.swift",
            "app/features/notes/note-panes/note-panes.swift", "app/features/study/quiz/quiz-solve-view/quiz-solve-view.swift",
            "app/features/notes/notes-model/notes-model.swift", "app/features/sessions/transcription/whisper.swift",
            "app/features/grades/catalog-view/catalog-view.swift",
        ]
        #expect(
            found(paths, "folder-name") == [
                "app/features/grades/catalog-view",
                "app/features/notes/note-panes", "app/features/notes/notes-model", "app/features/study/quiz/quiz-solve-view",
                "app/window/window-tabs", "sources/actions/core", "sources/domain/sessions/sessions",
                "sources/domain/window/shared",
            ])
    }

    @Test func moduleFoldersKeepTheirNames() {
        let paths = [
            "sources/core/entity.swift", "tests/unit/core/entity-tests.swift", "tests/unit/app/models/today-model-tests.swift",
            "tests/e2e/app/a11y-tests.swift", "app/folio-app.swift", "sources/tools/lint/main.swift",
            "sources/cli/generated/notes/note-add.swift",
        ]
        #expect(found(paths, "folder-name").isEmpty)
    }
}

@Suite struct AreaFolderTests {
    @Test func foldersOfAnAreaLayerAreAreas() {
        let paths = [
            "sources/domain/grades/grade.swift", "sources/domain/course/course.swift", "sources/actions/query/query.swift",
            "sources/actions/generated/actions.swift", "sources/actions/attendance/attendance-set.swift",
            "sources/cli/commands/window/open-command.swift", "sources/cli/commands/open/open-command.swift",
            "app/features/first-run/first-run-view.swift", "app/features/folder/first-run-view.swift",
            "app/platform/pdf-view/pdf-view.swift", "tests/unit/domain/layout/layout-tests.swift",
            "tests/unit/storage/notes/note-store-tests.swift", "sources/markdown/editing/fence.swift",
            "app/design/atoms/buttons/ghost-button.swift",
        ]
        #expect(
            found(paths, "area-folder") == [
                "app/features/first-run", "app/platform/pdf-view", "sources/actions/attendance", "sources/cli/commands/open",
                "sources/domain/course", "tests/unit/domain/layout",
            ])
    }

    @Test func layoutIsNowTheFolderArea() {
        #expect(Area.names.contains("folder"))
        #expect(!Area.names.contains("layout"))
    }
}
