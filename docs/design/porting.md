# 다른 앱으로 옮기기

다른 SwiftUI 앱에서 Folio와 같은 느낌을 만들 때의 순서다.

1. **토큰.** `app/design/tokens/`를 그대로 가져온다. `CourseAccent`의 프리셋은 그 앱의 강조색 하나로 바꾸고 `\.accent` 환경값은 남긴다. 강조색이 들어가는 구성 요소(`Badge(.accent)`, `ProgressBar`, `Checkbox`, `MonthCalendar`)가 이 값을 읽는다. `Swatch`는 웹 화면이 없으면 `Palette`에 합쳐도 된다.
2. **구성 요소.** `atoms/`, `components/`, `structures/`를 층 순서대로 가져온다. 두고 갈 것은 Folio의 데이터에 묶인 것들이다(`GradeLock`과 `.sensitive`, `GradeSteps`, `DdayBadge`, `tokens/notes/`의 `NoteStyle`, `structures/`의 `QuickAdd`와 `ItemMenu`). `DateChip`과 `MonthCalendar`는 `Workspace.calendar`를 읽으니 `Calendar` 환경값으로 바꾼다.
3. **창 틀.** Mac이면 [창 구조](window.md)의 Mac 절대로 창 재질, 본문 패널, 툴바 줄부터 만든다. 위치 표시가 필요 없으면 `Crumb` 관련 부분은 빼도 된다. iPad와 iPhone은 같은 문서의 iPad와 iPhone 절을 따른다.
4. **화면.** `Page { PageHeader; Block { Card { CardRow… } } }`로 쌓고, 폼은 [폼과 컨트롤](forms.md)을 따른다.
5. **검사.** `sources/tools/lint`의 디자인 규칙(`design-rules.swift`, `control-rules.swift`)을 가져온다. 규칙을 문서로만 두면 화면이 늘어날수록 금방 흐트러진다.

옮긴 뒤 화면을 이렇게 점검한다.

- 회색이 모두 따뜻한 쪽인가. `.secondary`, `Color.gray` 같은 시스템 회색이 남아 있지 않은가
- 색이 과목(강조)과 상태라는 두 가지 뜻으로만 쓰였나
- 입력과 선택이 모두 캡슐이고, 행 오른쪽에 붙어 있나. 테두리 있는 칸이 없나
- 채운 버튼이 화면에 하나 이하인가
- 모든 치수가 4pt 격자 위에 있고, 겹친 모서리가 안쪽 모서리 = 바깥 모서리 − 여백을 지키나
- 라이트와 다크를 모두 보았나. 유리 위의 칸이 불투명하게 뜨지 않나(`\.onGlass`)
- Mac에서 누를 수 있는 곳에 손가락 포인터가, 아이콘 버튼에 `.help`가 있나
