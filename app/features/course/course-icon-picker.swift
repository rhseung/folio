import SwiftUI

/// A course's icon from subject symbols grouped by field, searchable by Korean words, or none for the default book.
struct CourseIconPicker: View {
    @Binding var icon: String?
    let color: Color
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: Theme.Space.tight) {
                CourseMark(icon: icon, color: color)
                Image(systemName: "chevron.up.chevron.down").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary)
            }
            .chip()
        }
        .buttonStyle(.pointing(.plain))
        .help(Text(.iconPickerHelp))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            CourseIconPanel(icon: icon, color: color) {
                icon = $0
                open = false
            }
        }
    }
}

/// The picker's popover: a search line over the symbols grouped by field.
struct CourseIconPanel: View {
    let icon: String?
    let color: Color
    let choose: (String?) -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    struct Subject {
        let title: String
        /// Symbol name, then the words it is found by.
        let symbols: [(String, String)]
    }

    static let columns = 8

    // SF Symbols has no public catalog or Korean search terms, so the subject subset and its words live here.
    static let groups = [
        Subject(title: String(localized: .iconPickerFieldBasic), symbols: [(CourseMark.defaultIcon, "기본 책")]),
        Subject(title: String(localized: .iconPickerFieldMath), symbols: [
            ("function", "함수 수학 미적분"), ("sum", "합 시그마 급수 수열"), ("x.squareroot", "루트 제곱근 대수"),
            ("percent", "퍼센트 비율 확률"), ("plus.forwardslash.minus", "사칙연산 산수 계산"), ("divide", "나눗셈 정수론"),
            ("equal", "등식 방정식"), ("infinity", "무한 극한 해석학"), ("pi", "파이 원주율"), ("number", "수 정수론 숫자"),
            ("angle", "각도 삼각함수 기하"), ("triangle", "삼각형 기하"), ("skew", "선형대수 변환 행렬"),
            ("point.3.filled.connected.trianglepath.dotted", "그래프 이론 이산수학 네트워크"),
            ("chart.xyaxis.line", "좌표 그래프 함수"), ("chart.dots.scatter", "통계 산점도 회귀 데이터"),
            ("chart.bar", "통계 막대 분포"), ("dice", "확률 주사위 통계"), ("ruler", "측정 자 기하"),
            ("square.grid.3x3", "행렬 격자 선형대수"),
        ]),
        Subject(title: String(localized: .iconPickerFieldScience), symbols: [
            ("atom", "원자 물리 양자 화학"), ("flask", "화학 실험 플라스크"), ("testtube.2", "시험관 실험 화학 생화학"),
            ("microbe", "미생물 세포 생물"), ("allergens", "분자 화학 생명"), ("leaf", "식물 생물 생태 환경"),
            ("tree", "나무 생태 환경"), ("ladybug", "곤충 생물"), ("fish", "물고기 생물 해양"), ("pawprint", "동물 생물"),
            ("brain", "뇌 신경 과학"), ("lungs", "폐 생리 해부"), ("waveform.path.ecg", "심전도 생리 의학"),
            ("drop", "물 유체 액체"), ("flame", "불 열 연소 열역학"), ("thermometer.medium", "온도 열역학"),
            ("sun.max", "태양 에너지 천문"), ("moon.stars", "천문 우주 별"), ("globe.asia.australia", "지구 지구과학"),
            ("mountain.2", "산 지질 지구과학"), ("hurricane", "기상 대기 날씨"), ("laser.burst", "레이저 광학 물리"),
            ("scope", "광학 조준"), ("binoculars", "관측 광학"),
        ]),
        Subject(title: String(localized: .iconPickerFieldEngineering), symbols: [
            ("bolt", "전기 전류 전자기"), ("cpu", "반도체 프로세서 컴퓨터구조"), ("memorychip", "메모리 칩 반도체 회로"),
            ("waveform", "신호 파형 신호처리 소리"), ("antenna.radiowaves.left.and.right", "통신 안테나 전파 무선"),
            ("cable.connector", "케이블 회로 전자"), ("powerplug", "전력 전기"), ("battery.100", "배터리 전지 에너지"),
            ("lightbulb", "전구 아이디어 설계"), ("gearshape.2", "기계 톱니 동역학"), ("wrench.and.screwdriver", "도구 실습 제작"),
            ("hammer", "망치 제작 건설"), ("gauge.with.dots.needle.33percent", "계측 측정 제어"), ("fan", "유체 열 기계"),
            ("engine.combustion", "엔진 기계 열"), ("car", "자동차 기계 모빌리티"), ("airplane", "항공 우주 비행"),
            ("sailboat", "배 조선 해양"), ("train.side.front.car", "기차 교통"), ("building.2", "건축 토목 도시"),
            ("cube", "입체 설계 재료"), ("shippingbox", "물류 산업"), ("wind", "바람 공기 유체"), ("water.waves", "파동 유체 해양"),
        ]),
        Subject(title: String(localized: .iconPickerFieldComputer), symbols: [
            ("terminal", "터미널 시스템 셸"), ("chevron.left.forwardslash.chevron.right", "코드 프로그래밍 웹"),
            ("curlybraces", "코드 프로그래밍 언어"), ("desktopcomputer", "컴퓨터 데스크톱"), ("laptopcomputer", "노트북 컴퓨터"),
            ("keyboard", "키보드 입력"), ("network", "네트워크 인터넷"), ("server.rack", "서버 시스템 분산"),
            ("externaldrive", "저장 장치 파일"), ("cylinder.split.1x2", "데이터베이스 저장"), ("cloud", "클라우드"),
            ("lock", "보안 암호"), ("key", "암호 키 보안"), ("shield", "보안 방어"), ("link", "링크 연결"),
            ("arrow.triangle.branch", "분기 버전 알고리즘"), ("point.3.connected.trianglepath.dotted", "그래프 자료구조 네트워크"),
            ("square.stack.3d.up", "스택 계층 자료구조"), ("tablecells", "표 데이터 스프레드시트"), ("sparkles", "인공지능 AI 생성"),
            ("eye", "비전 시각 인식"), ("puzzlepiece", "퍼즐 문제 해결"), ("gamecontroller", "게임"), ("text.magnifyingglass", "검색 정보 텍스트"),
        ]),
        Subject(title: String(localized: .iconPickerFieldSociety), symbols: [
            ("wonsign.circle", "원 돈 경제"), ("dollarsign.circle", "달러 돈 경제 금융"), ("banknote", "돈 화폐 회계"),
            ("creditcard", "카드 금융 결제"), ("chart.line.uptrend.xyaxis", "성장 추세 경제 주식"), ("chart.pie", "비율 통계 경영"),
            ("briefcase", "경영 창업 직업"), ("building.columns", "기관 정치 법 역사"), ("scalemass", "저울 법 정의 무게"),
            ("person.2", "사람 사회 관계"), ("person.3", "사람 집단 조직"), ("megaphone", "홍보 마케팅 광고"),
            ("newspaper", "신문 언론 미디어"), ("flag", "깃발 국가 정치"), ("map", "지도 지리"), ("globe", "세계 국제 글로벌"),
            ("signpost.right", "방향 진로 정책"), ("cart", "소비 시장 유통"), ("storefront", "가게 상업 창업"),
            ("person.line.dotted.person", "협력 협상 거래"), ("hand.raised", "참여 권리 인권"),
        ]),
        Subject(title: String(localized: .iconPickerFieldHumanities), symbols: [
            ("book", "책 독서"), ("books.vertical", "책 도서관 문헌"), ("text.book.closed", "교과서 책"),
            ("character.book.closed", "사전 어휘 언어"), ("character", "글자 문자 언어"),
            ("textformat", "글꼴 텍스트 글쓰기"), ("quote.opening", "인용 문학"), ("text.quote", "인용 논문 글"),
            ("bubble.left.and.bubble.right", "대화 토론 회화 소통"), ("character.bubble", "회화 외국어 언어"),
            ("translate", "번역 외국어 영어"), ("pencil", "연필 필기 글쓰기"), ("pencil.and.scribble", "작문 글쓰기"),
            ("scroll", "두루마리 역사 고전"), ("hourglass", "시간 역사"), ("crown", "왕 역사 권력"),
            ("brain.head.profile", "심리 인지 사고 철학"), ("graduationcap", "교육 졸업 학위"), ("person.bust", "인물 초상"),
            ("magazine", "잡지 교양 읽기"), ("bookmark", "책갈피 읽기"),
        ]),
        Subject(title: String(localized: .iconPickerFieldArts), symbols: [
            ("paintbrush", "그림 미술 회화"), ("paintpalette", "팔레트 미술 색"), ("paintbrush.pointed", "붓 서예 미술"),
            ("pencil.tip", "스케치 드로잉 디자인"), ("scribble", "드로잉 낙서"), ("music.note", "음악 음표"),
            ("music.note.list", "음악 악보 곡"), ("pianokeys", "피아노 건반 음악"), ("guitars", "기타 악기 음악"),
            ("music.mic", "노래 보컬 마이크"), ("headphones", "듣기 오디오 음악"), ("theatermasks", "연극 공연 드라마"),
            ("camera", "사진 카메라"), ("film", "영화 필름 영상"), ("video", "영상 비디오 촬영"),
            ("figure.walk", "걷기 체육 운동"), ("figure.run", "달리기 체육 운동"), ("sportscourt", "체육 경기 스포츠"),
            ("soccerball", "축구 스포츠"), ("basketball", "농구 스포츠"), ("dumbbell", "운동 헬스 체력"),
            ("figure.yoga", "요가 운동"), ("heart", "심장 건강 사랑"), ("cross.case", "의학 응급 보건"),
            ("stethoscope", "의학 진료 간호"), ("pills", "약 약학"), ("fork.knife", "요리 식품 영양"),
            ("cup.and.saucer", "카페 휴식 차"),
        ]),
    ]

    /// Groups still showing for the query: a matching group title keeps the whole group, otherwise only matching symbols.
    var shown: [Subject] {
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return Self.groups }
        return Self.groups.compactMap { group in
            let symbols = group.symbols.filter { s in
                words.allSatisfy { w in [group.title, s.0, s.1].contains { $0.localizedCaseInsensitiveContains(w) } }
            }
            return symbols.isEmpty ? nil : Subject(title: group.title, symbols: symbols)
        }
    }

    var body: some View {
        let groups = shown
        let cell = Theme.Size.toolbarButton
        return VStack(spacing: 0) {
            HStack(spacing: Theme.Space.tight) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textTertiary)
                TextField(String(localized: .iconPickerSearch), text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if let first = groups.first?.symbols.first { choose(first.0) } }
            }
            .padding(Theme.Space.m)
            Theme.Palette.line.frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    if groups.isEmpty {
                        EmptyLine(String(localized: .iconPickerNoMatch)).padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    LazyVStack(alignment: .leading, spacing: Theme.Space.s) {
                        ForEach(groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Caption(group.title)
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: Theme.Space.xs), count: Self.columns),
                                          alignment: .leading, spacing: Theme.Space.xs) {
                                    ForEach(group.symbols, id: \.0) { symbol, words in
                                        self.cell(symbol, name: words.split(separator: " ").first.map(String.init) ?? symbol).id(symbol)
                                    }
                                }
                            }
                        }
                    }
                    .padding(Theme.Space.m)
                }
                .onAppear { if let icon { proxy.scrollTo(icon, anchor: .center) } }
            }
            // Fixed so the popover doesn't jump in size as the search narrows the grid.
            .frame(height: 340)
        }
        .frame(width: cell * CGFloat(Self.columns) + Theme.Space.xs * CGFloat(Self.columns - 1) + Theme.Space.m * 2)
        .font(Theme.Typeface.body)
        .onAppear {
            query = ""
            focused = true
        }
    }

    func cell(_ symbol: String, name: String) -> some View {
        // The default cell stands for no icon, so a course left on the default keeps following CourseMark.defaultIcon.
        let value = symbol == CourseMark.defaultIcon ? nil : symbol
        let chosen = value == icon
        return Button { choose(value) } label: {
            LineIcon(symbol: symbol, filled: chosen)
                .foregroundStyle(chosen ? color : Theme.Palette.textSecondary)
                .frame(width: Theme.Size.toolbarButton, height: Theme.Size.toolbarButton)
                .background(chosen ? color.opacity(Theme.Opacity.tint) : .clear, in: .rect(cornerRadius: Theme.Radius.control))
                .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
