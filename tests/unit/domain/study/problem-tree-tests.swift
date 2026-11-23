import FolioCore
import FolioDomain
import Foundation
import Testing

struct ProblemTreeTests {
    let warmUp = ProblemGroup(number: "W", title: "Warm-up", text: "Warm-up Problems (Do not submit)")
    let three = ProblemGroup(number: "3", text: "Let $G$ be the graph below.")

    // 지문과 문제가 따로 놓여도 나무는 문제지의 차례를 따른다. W는 W1이 1번보다 먼저 나오므로 1번 앞이다.
    @Test func siblingsFollowTheSheetAndSolvingWalksDepthFirst() {
        let problems = [
            Problem(number: "W1", parent: "W"), Problem(number: "1"), Problem(number: "W2", parent: "W"),
            Problem(number: "3a", parent: "3"), Problem(number: "2"), Problem(number: "3b", parent: "3"),
        ]
        let tree = ProblemTree(problems: problems, groups: [three, warmUp])
        #expect(tree.roots.map(\.number) == ["W", "1", "3", "2"])
        #expect(tree.questions.map(\.number) == ["W1", "W2", "1", "3a", "3b", "2"])
        #expect(tree.roots[0].children.map(\.depth) == [1, 1])
        #expect(tree.groups.map(\.number) == ["W", "3"])
    }

    @Test func aStemHoldsSubStemsLikeFolders() {
        let inner = ProblemGroup(number: "W1", parent: "W", text: "For each graph below,")
        let problems = [Problem(number: "W1a", parent: "W1"), Problem(number: "W1b", parent: "W1"), Problem(number: "W2", parent: "W")]
        let tree = ProblemTree(problems: problems, groups: [warmUp, inner])
        #expect(tree.questions.map(\.number) == ["W1a", "W1b", "W2"])
        #expect(tree.path(to: problems[1].id) == ["Warm-up", "W1", "W1b"])
        #expect(tree.stems(of: problems[0].id).map(\.number) == ["W", "W1"])
        #expect(tree.stems(of: problems[2].id).map(\.number) == ["W"])
    }

    // 지문은 풀 문제가 아니다. 풀 문제가 없는 지문은 나무에 남지 않는다.
    @Test func onlyQuestionsCountAndEmptyStemsLeave() {
        let lonely = ProblemGroup(number: "9", text: "Read the instructions.")
        let tree = ProblemTree(problems: [Problem(number: "1")], groups: [lonely, warmUp])
        #expect(tree.roots.map(\.number) == ["1"] && tree.groups.isEmpty && tree.questions.count == 1)
    }

    // 예전처럼 상위 번호가 문제이면 그 문제 아래에 둔다. 같은 번호의 문제가 둘이어도, 고리가 있어도 문제를 잃거나 두 번 넣지 않는다.
    @Test func oddParentsKeepEveryQuestionOnce() {
        let loop = [Problem(number: "x", parent: "y"), Problem(number: "y", parent: "x")]
        let twins = [Problem(number: "4"), Problem(number: "4"), Problem(number: "4a", parent: "4")]
        let looping = ProblemGroup(number: "A", parent: "B", text: ""), back = ProblemGroup(number: "B", parent: "A", text: "")
        let tree = ProblemTree(problems: loop + twins + [Problem(number: "z", parent: "A")], groups: [looping, back])
        let ids = tree.questions.map(\.id)
        #expect(ids.count == 6 && Set(ids).count == 6)
        #expect(tree.roots.first { $0.number == "4" }?.children.map(\.number) == ["4a"])
        #expect(tree.path(to: twins[2].id) == ["4", "4a"])
    }

    @Test func studyWalksTheTreeAndCountsOnlyQuestions() {
        let device = UUID(), now = Date(timeIntervalSince1970: 1_790_000_000)
        var file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        let problems = [Problem(number: "1"), Problem(number: "W1", parent: "W"), Problem(number: "W2", parent: "W")]
        file.problemSets = [
            ProblemSet(device: device, at: now, title: "HW4", problems: [problems[1], problems[0], problems[2]], groups: [warmUp])
        ]
        let study = CourseStudy(
            file: file, cards: [], log: StudyLog(), settings: Settings(), calendar: Calendar(identifier: .gregorian), now: now)
        #expect(study.allProblems.map(\.problem.number) == ["W1", "W2", "1"])
    }
}
