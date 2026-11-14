import FolioDomain
import Foundation
import Testing

@testable import FolioLMS

// 마크업은 2026-11-13에 읽은 Coursemos 페이지의 모양이고, 과목과 글은 지어낸 것이다.
struct LMSPagesTests {
    static let dashboard = """
        <div class="course_box"><a class="course_link" href="https://lms.gist.ac.kr/course/view.php?id=27967">
          <div class="course-image"><img class="courseimage"></div>
          <div class="course-name"><div class="course-label"><div class="label label-course">교과(오프라인)</div>
            <div class="label label-course label-under">학부</div></div>
            <div class="course-title"><h3>그래프 이론[01]<span class="new">NEW</span></h3><p class="prof">김교수</p></div></div></a></div>
        <div class="course_box"><a class="course_link" href="https://lms.gist.ac.kr/course/view.php?id=28011">
          <div class="course-name"><div class="course-label"><div class="label label-course">교류강좌</div></div>
            <div class="course-title"><h3>안전 교육</h3><p class="prof"></p></div></div></a></div>
        <div class="course_box"><a class="course_link" href="https://lms.gist.ac.kr/course/view.php?id=27967">again</a></div>
        """

    static let assignments = """
        <div id="region-main"><table class="generaltable"><thead><tr><th>주</th><th>과제</th><th>종료 일시</th><th>제출</th><th>성적</th></tr></thead>
        <tbody>
        <tr><td class="cell c0">3주차 [9월14일 - 9월20일]</td><td class="cell c1"><a href="https://lms.gist.ac.kr/mod/assign/view.php?id=139941">Homework Set #1</a></td>
          <td class="cell c2">2026-09-14 23:55</td><td class="cell c3">제출 완료</td><td class="cell c4 lastcol">100.00</td></tr>
        <tr><td><div class="tabledivider"></div></td></tr>
        <tr><td class="cell c0"></td><td class="cell c1"><a href="https://lms.gist.ac.kr/mod/assign/view.php?id=139950">Homework Set #5</a></td>
          <td class="cell c2">2026-11-20 23:55</td><td class="cell c3">미제출</td><td class="cell c4 lastcol">-</td></tr>
        </tbody></table></div>
        """

    static let files = """
        <div id="region-main"><table class="generaltable mod_index"><thead><tr><th>주</th><th>제목</th><th>설명</th></tr></thead><tbody>
        <tr><td class="cell c0">1주차 [8월31일 - 9월6일]</td><td class="cell c1"><a href="view.php?id=139109"><img class="activityicon">Course Syllabus</a></td><td class="cell c2 lastcol"></td></tr>
        <tr><td class="cell c0"></td><td class="cell c1"><a href="view.php?id=139110"><img class="activityicon">01_Intro</a></td><td class="cell c2 lastcol"><div class="no-overflow"><p>slides</p></div></td></tr>
        <tr><td><div class="tabledivider"></div></td></tr>
        <tr><td class="cell c0">5주차 [9월28일 - 10월4일]</td><td class="cell c1"><a href="view.php?id=139200"><img class="activityicon">05_Matchings</a></td><td class="cell c2 lastcol"></td></tr>
        </tbody></table></div>
        """

    static let notices = """
        <table class="ubboard_table table"><thead><tr><th>번호</th><th>제목</th><th>작성자</th><th>작성일</th><th>조회수</th></tr></thead><tbody>
        <tr><td class="tcenter">7</td><td><a href="https://lms.gist.ac.kr/mod/ubboard/article.php?ls=15&amp;id=139001&amp;bwid=23464"><strong>[그래프 이론[01]]</strong> 중간고사 안내</a></td>
          <td class="tcenter">조교</td><td class="tcenter">2026-10-12</td><td class="tcenter">74</td></tr>
        </tbody></table>
        """

    // 사용자가 보낸 Slow Problem #2 과제 페이지의 모양이다. 마감 줄 아래 파일 트리에 첨부가 있다.
    static let assignmentPage = """
        <div id="region-main"><h2>Slow Problem #2</h2>
        <div id="intro" class="box generalbox boxaligncenter"><div class="no-overflow"><p>Due: November 19, Thursday, 11:55pm</p></div>
        <div id="assign_files_tree5f3a" class="ygtv"><ul><li><div><img class="icon" alt="">
          <a href="https://lms.gist.ac.kr/pluginfile.php/402311/mod_assign/introattachment/0/slow_problem_2.pdf?forcedownload=1">slow_problem_2.pdf</a></div></li>
          <li><div><a href="https://lms.gist.ac.kr/pluginfile.php/402311/mod_assign/introattachment/0/%EC%B0%B8%EA%B3%A0%20%EC%9E%90%EB%A3%8C.pdf?forcedownload=1">참고 자료.pdf</a></div></li>
          <li><div><a href="https://lms.gist.ac.kr/pluginfile.php/402311/mod_assign/introattachment/0/slow_problem_2.pdf?forcedownload=1">slow_problem_2.pdf</a></div></li>
        </ul></div></div>
        <div class="submissionstatustable"><table class="generaltable"><tbody><tr><td>제출 여부</td><td>제출 안 함</td></tr></tbody></table>
          <a href="https://lms.gist.ac.kr/pluginfile.php/402311/assignsubmission_file/submission_files/1/old.pdf">old.pdf</a></div></div>
        """

    @Test func readsClassrooms() throws {
        let rooms = try LMSPages.classrooms(Self.dashboard)
        #expect(
            rooms == [
                LMSClassroom(id: 27967, title: "그래프 이론[01]", kind: "교과(오프라인)", professors: "김교수"),
                LMSClassroom(id: 28011, title: "안전 교육", kind: "교류강좌", professors: nil),
            ])
    }

    @Test func readsAssignments() throws {
        let a = try LMSPages.assignments(Self.assignments, classroom: 27967)
        #expect(a.map(\.id) == [139941, 139950])
        #expect(a.map(\.submitted) == [true, false])
        // 한국 시간 23:55는 UTC 14:55이다.
        #expect(a[1].due == ISO8601DateFormatter().date(from: "2026-11-20T14:55:00Z"))
    }

    @Test func readsFilesWithTheirWeek() throws {
        let f = try LMSPages.files(Self.files, classroom: 27967)
        #expect(f.map(\.title) == ["Course Syllabus", "01_Intro", "05_Matchings"])
        #expect(f.map(\.week) == ["1주차 [8월31일 - 9월6일]", "1주차 [8월31일 - 9월6일]", "5주차 [9월28일 - 10월4일]"])
        #expect(f[2].url.absoluteString == "https://lms.gist.ac.kr/mod/ubfile/view.php?id=139200")
    }

    @Test func readsNoticesWithoutTheClassroomPrefix() throws {
        let n = try LMSPages.notices(Self.notices, classroom: 27967)
        #expect(
            n == [
                LMSNotice(
                    id: 23464, board: 139001, classroom: 27967, title: "중간고사 안내", author: "조교",
                    posted: ISO8601DateFormatter().date(from: "2026-10-11T15:00:00Z"))
            ])
    }

    @Test func readsAssignmentAttachmentsButNotSubmissions() throws {
        let a = try LMSPages.attachments(Self.assignmentPage)
        #expect(a.map(\.name) == ["slow_problem_2.pdf", "참고 자료.pdf"])
        #expect(a[0].path == "/pluginfile.php/402311/mod_assign/introattachment/0/slow_problem_2.pdf?forcedownload=1")
        #expect(
            a[1].url.absoluteString
                == "https://lms.gist.ac.kr/pluginfile.php/402311/mod_assign/introattachment/0/%EC%B0%B8%EA%B3%A0%20%EC%9E%90%EB%A3%8C.pdf?forcedownload=1"
        )
        #expect(try LMSPages.attachments(Self.assignments).isEmpty)
    }

    @Test func tellsTheLoginForm() {
        #expect(
            LMSPages.isLogin(
                #"<form method="post" action="https://lms.gist.ac.kr/login/index.php"><input type="password" name="password"></form>"#))
        #expect(!LMSPages.isLogin(Self.dashboard))
    }

    @Test func encodesFormValuesThatLookLikeSyntax() {
        #expect(
            LMSClient.form(["username": "20250001", "password": "a+b&c=d 한"]) == "username=20250001&password=a%2Bb%26c%3Dd%20%ED%95%9C")
    }
}
