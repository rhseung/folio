/// `folio help <topic>`: concepts rather than commands (docs/SPEC.md "도움말").
enum Topic: String, CaseIterable {
    case refs, output, exit, safety, fzf

    static let aliases: [String: Topic] = ["가리키기": .refs, "출력": .output, "종료코드": .exit, "종료-코드": .exit, "exit-codes": .exit, "안전": .safety]

    init?(_ name: String) {
        guard let t = Topic(rawValue: name) ?? Self.aliases[name] else { return nil }
        self = t
    }

    var title: String {
        switch self {
        case .refs: "가리키기"
        case .output: "출력"
        case .exit: "종료 코드"
        case .safety: "안전"
        case .fzf: "fzf"
        }
    }

    var body: [String] {
        switch self {
        case .refs: [
            "과목은 강의 코드(EC4207), 폴더 이름, 과목 이름, UUID로 가리킨다. 대소문자와 띄어쓰기는 가리지 않는다.",
            "과목 안의 항목은 <과목>/<항목>으로 쓴다. 회차는 9주차-1, 시험과 과제와 단원은 제목, 자료와 노트는 경로나 파일 이름.",
            "정확히 맞는 이름이 없으면 그 글자를 포함한 이름을 찾는다. 여러 개에 맞으면 실행하지 않고 후보를 보여 준다(종료 코드 3).",
            "학기를 생략하면 오늘이 든 학기를 쓴다.",
            "set 명령에서 값을 지우려면 none을 준다(--due none). 여러 번 받는 옵션에 none만 주면 목록을 비운다.",
            "",
            "  folio session show EC4207/9주차-1",
            "  folio exam show 그래프/Quiz1",
        ]
        case .output: [
            "기본 출력은 사람이 읽는 형식이다. 터미널이 아니거나 NO_COLOR가 있으면 색과 링크를 끈다.",
            "--json이면 표준 출력에 JSON 값 하나만 쓴다. 필드 이름과 날짜 형식은 course.json과 같다.",
            "쓰기 명령의 JSON은 {action, dryRun, made, changes}다. changes의 각 항목은 {kind, path, item, to, fields}. fields는 바뀐 필드마다 {name, before, after}다.",
            "오류는 표준 오류에 쓴다. --json이면 {\"error\": {\"code\", \"message\", \"candidates\"}}.",
            "",
            "  folio session list EC4207 --json | jq '.[0]'",
        ]
        case .exit: [
            "0 성공",
            "1 예기치 못한 오류",
            "2 사용법 오류 (없는 옵션, 맞지 않는 JSON 입력)",
            "3 대상을 찾지 못했거나 여러 개에 맞음",
            "4 규칙 위반 (노트가 연결된 회차 지우기, 끝이 시작보다 이른 시험)",
            "5 확인이 필요한데 --yes가 없음, 또는 성적 잠금을 풀지 못함 (folio unlock)",
            "6 다른 곳에서 바뀌어 충돌함",
            "7 커버리지 검사 실패 (folio actions --check)",
        ]
        case .safety: [
            "모든 쓰기 명령은 --dry-run을 받는다. 쓰지 않고 + 추가, ~ 변경, - 삭제, → 이동으로 바뀔 것을 보여 준다.",
            "이동, 이름 변경, 휴지통, 여러 항목을 한 번에 바꾸는 명령은 확인을 받는다. 터미널이면 [y/N]으로 묻고, 아니면 --yes가 있어야 한다.",
            "에이전트는 사용자가 승인한 뒤에만 --yes를 붙인다.",
            "이동과 이름 변경은 .folio/moves.jsonl에 남고 folio cleanup undo <묶음 ID>로 되돌린다. 지운 노트와 자료는 휴지통에 있다.",
            "명령줄 도구는 앱과 다른 기기 ID로 로그를 쓴다. 앱이 켜져 있어도 된다. 앱은 바뀐 파일을 다시 읽는다.",
        ]
        case .fzf: [
            "터미널에서 항목 인자를 빼고 실행하면 fzf로 고른다. 오른쪽에는 고른 항목의 show를 보여 준다. 과목만 주면(folio exam show EC4207) 그 과목 안에서 고른다.",
            "회차나 단원을 여러 개 받는 인자는 Tab으로 여러 개를 고른다(folio unit link EC4207/트리).",
            "터미널이 아니거나 --json, --no-pick, FOLIO_NO_PICK이면 고르지 않고 사용법 오류(종료 코드 2)로 끝난다.",
            "",
            "목록 명령은 --lines를 받는다. 한 줄에 하나, 탭으로 나누고, 첫 칸은 다른 명령에 넘길 수 있는 참조다.",
            "",
            "  folio session list EC4207 --lines | fzf --delimiter '\\t' --with-nth 2.. --preview 'folio session show {1}' | cut -f1 | xargs folio session show",
            "",
            "fzf는 따로 설치한다. 없어도 모든 명령이 동작한다.",
        ]
        }
    }

    static func overview() -> [String] {
        ["주제:".styled(.bold)] + allCases.map { "  \($0.rawValue.padded(to: 8)) \($0.title)" } + ["", "  folio help <주제>".styled(.dim)]
    }

    func print() {
        say(title.styled(.bold))
        for line in body { say(line.hasPrefix("  folio") ? line : line.styled(line.first?.isNumber == true ? .bold : .dim)) }
    }
}
