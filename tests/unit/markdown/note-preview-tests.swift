import FolioMarkdown
import Testing

struct NotePreviewTests {
    @Test func previewSkipsFrontmatterHeadingsCodeAndTables() {
        let note = """
            ---
            id: 1
            ---
            # 매칭

            Hall 조건 **|N(S)| ≥ |S|**을 [[König–Hall|정리]]로 본다. ^hall

            ```swift
            let x = 1
            ```

            | a | b |
            | - | - |
            | 1 | 2 |

            - 필요 조건은 바로 보인다
            - [ ] 충분 조건은 [증명](https://example.com)을 본다

            > [!note] 모르는 것
            > 정점 덮개와 ![[그림.svg]] 독립 집합
            """
        #expect(
            NotePreview.text(of: note)
                == "Hall 조건 |N(S)| ≥ |S|을 정리로 본다. 필요 조건은 바로 보인다 충분 조건은 증명을 본다 모르는 것 정점 덮개와 독립 집합")
    }

    @Test func previewStopsAtTheLimit() {
        let note = String(repeating: "가나다라 ", count: 100)
        #expect(NotePreview.text(of: note, limit: 20).count == 20)
        #expect(NotePreview.text(of: "# 제목만").isEmpty)
    }

    @Test func texPreviewReadsTheDocumentBodyWithoutCommandsOrComments() {
        let note = """
            \\documentclass{article}
            \\usepackage{amsmath}
            \\begin{document}
            \\section{매칭}
            최대 매칭의 크기는 % 나중에 고친다
            최소 정점 덮개의 크기와 같다.
            \\end{document}
            """
        #expect(NotePreview.text(of: note, tex: true) == "최대 매칭의 크기는 최소 정점 덮개의 크기와 같다.")
    }
}
