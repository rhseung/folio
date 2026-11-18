import FolioDomain
import Foundation
import Testing

// PR의 패치 노트 검사(.mise/tasks/patch-notes-check)는 Linux에서 돌아 PatchNotes를 부르지 못하고 같은 읽기를 셸로 옮겨 둔다.
// 둘이 어긋나면 검사를 통과한 PR이 릴리스되지 않거나 그 반대가 되므로, 같은 본문에 같은 답을 내는지 본다.
struct PatchNotesCheckTests {
    static let script = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../.mise/tasks/patch-notes-check")
        .standardized

    static let bodies = [
        "요약\n\n## 패치 노트\n- fix: 칸 닫기",
        "## 패치 노트\r\n* change : 칩이 흐리게 보임 (folio://today)\r\n",
        "## 패치 노트\n\t-\tfeat: 탭으로 시작하는 줄",
        "##   패치 노트  \n- feat: 제목 뒤 공백",
        "## 패치 노트\n#415 관련 메모\n### fix\n- fix: 소제목 뒤의 항목",
        "## 패치 노트\n- fix: 수식 (folio://a) 링크 (folio://settings/recording)",
        "",
        "CI만 고쳤습니다.",
        "## 패치 노트\n",
        "## 패치 노트\n- feature: 종류가 아님\n- 새 기능: 번역한 종류\n- fix:\n- fix:   \n- fix: (folio://today)",
        "## 패치 노트\n- fix\t: 탭 뒤의 쌍점",
        "## 패치 노트 추가\n- fix: 다른 제목",
        "### 패치 노트\n- fix: 3단계 제목",
        "## 확인\n- fix: 다른 절\n## 패치 노트",
        "## 패치 노트\n## 확인\n- fix: 절이 끝난 뒤",
        "# 패치 노트\n- fix: 1단계 제목",
        "## 패치 노트\n####### 일곱 개는 제목이 아님\n- change: 그 뒤",
    ]

    static func check(_ body: String) throws -> Bool {
        let process = Process()
        process.executableURL = script
        process.arguments = ["--body-only"]
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data(body.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    @Test(arguments: Self.bodies)
    func theCheckReadsABodyAsTheReleaseDoes(_ body: String) throws {
        #expect(try Self.check(body) == !PatchNotes.items(in: body).isEmpty, "\(body.debugDescription)")
    }
}
