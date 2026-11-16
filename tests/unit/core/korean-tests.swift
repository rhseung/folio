import FolioCore
import Testing

struct KoreanTests {
    @Test func particlesFollowTheLastSyllable() {
        #expect(Korean.subject("시험") == "시험이")
        #expect(Korean.subject("과제") == "과제가")
        #expect(Korean.object("항목") == "항목을")
        #expect(Korean.object("ABC") == "ABC를")
    }
}
