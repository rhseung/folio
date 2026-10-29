import FolioAI
import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct ClaudeModelTests {
    @Test func aContextItemAddedAgainMovesToTheEndAndComesBackFromRemoved() throws {
        let model = ClaudeModel(workspace: try fixtureWorkspace())
        let a = ContextBuilder.material(path: "Lectures/a.pdf", text: "a"), b = ContextBuilder.material(path: "Lectures/b.pdf", text: "b")
        model.add(a)
        model.add(b)
        model.remove(a)
        model.add(a)
        #expect(model.added.map(\.id) == [b.id, a.id])
        #expect(model.removed.isEmpty)
        model.add(nil)
        #expect(model.added.count == 2)
    }

    @Test func switchingChatsClearsTheLastMessageAndRetry() throws {
        let model = ClaudeModel(workspace: try fixtureWorkspace())
        model.status = "복사했습니다"
        model.failed = "질문"
        model.select(nil)
        #expect(model.status == nil && model.failed == nil && model.chatID == nil)
        #expect(model.chatOptions.map(\.title) == ["새 대화"])
    }

    @Test func loadingACourseReadsItsChatsAndNotes() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        #expect(model.chats.isEmpty && model.chatID == nil)
        #expect(model.notes.map(\.title) == ["2주차-1"])
        #expect(model.addOptions(course).first?.section == "노트")
    }

    @Test func anAnswerIsNamedByItsFirstHeading() {
        #expect(ClaudeModel.noteTitle("intro\n# 매칭 정리 \n## 더") == "매칭 정리")
        #expect(ClaudeModel.noteTitle("## 둘째 수준만") == nil)
    }

    @Test func errorsReadAsSentences() {
        #expect(ClaudeModel.message(for: ClaudeError.http(status: 401, body: "")) == "인증에 실패했습니다. API 키나 Claude Code 로그인을 확인하세요.")
        #expect(ClaudeModel.message(for: ClaudeError.http(status: 500, body: "")) == "요청이 실패했습니다 (HTTP 500).")
        #expect(ClaudeModel.message(for: ClaudeError.http(status: 0, body: "cli says no")) == "요청이 실패했습니다: cli says no")
    }

    @Test func withoutUnitsTheCardLinkIsOff() {
        var chat = Chat(device: UUID(), at: .now)
        chat.messages = [ChatMessage(role: .user, text: "질문", at: .now), ChatMessage(role: .assistant, text: "답", at: .now)]
        #expect(ClaudeModel.html(chat, cards: false).contains(#"<span class="off""#))
        #expect(ClaudeModel.html(chat, cards: true).contains("folio://action/card/"))
        #expect(ClaudeModel.html(chat, partial: "쓰는 중").contains("쓰는 중"))
    }
}
