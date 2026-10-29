# Folio

과목을 중심으로 강의 자료, 노트, 복습, 퀴즈, 과제, 성적을 한곳에서 관리하는 macOS와 iPadOS용 앱입니다. 한 사람의 학업에 맞춰 만드는 개인용 앱이며, 학점과 졸업 요건 규칙은 GIST 학사편람을 따릅니다.

## 주요 기능

- **오늘**: 다가오는 시험의 D-day, 오늘 복습할 강의 회차와 단원, 남은 과제, 오늘 수업, 최근 2주의 공부 시간을 한 화면에 모읍니다.
- **과목**: 강의 회차와 출결, 단원, 시험과 시험 범위, 과제, 자료(PDF), 노트, 과목 성적을 과목 페이지 하나에서 다룹니다.
- **노트**: 노트는 실시간 미리보기를 갖춘 마크다운 편집기(CodeMirror 6)에서 작성합니다. KaTeX와 AsciiMath 수식, 정의와 정리 같은 callout, wikilink를 지원합니다.
- **복습**: 날짜가 아니라 단원 단위로 간격을 두고 복습합니다. 밀린 단원은 우선순위대로 보여 줍니다.
- **퀴즈**: 카드를 만들어 풀고, 서술형 답은 Claude가 채점합니다. 오답과 통계를 모으고, 종이로 푸는 문제 묶음도 기록합니다.
- **성적**: 평가 기준에 따라 환산 점수를 계산하고, 학기 평점, 누적 평점, 전공 평점과 목표 학점까지 필요한 점수, 졸업 요건의 진행 상황을 보여 줍니다.
- **강의 녹음**: 강의를 녹음하고 기기 안에서 글로 받아씁니다.
- **Claude 패널**: 지금 보는 과목의 맥락을 함께 넘겨 Claude에게 질문합니다.
- **검색**: 모든 과목의 노트, 자료 제목과 PDF 본문, 퀴즈, 과제를 찾습니다.
- **명령줄 도구 `folio`**: 앱에서 할 수 있는 데이터 조작을 터미널과 AI 에이전트에서도 할 수 있습니다.

손필기(PencilKit), 위젯, PDF 내보내기는 아직 만들지 않았습니다. 전체 기능과 결정 사항은 [명세](docs/SPEC.md)에 있습니다.

## 데이터 원칙

- 모든 데이터의 원본은 iCloud Drive의 학업 폴더에 있는 파일입니다. 과목 정보(`course.json`), 성적표(`transcript.json`), 마크다운 노트, 기기별 로그(`.jsonl`)가 모두 그 폴더에 있습니다. 앱의 SQLite 검색 색인은 캐시이므로, 지워도 앱이 파일에서 다시 만듭니다.
- 폴더 구조는 Folio가 정한 표준 구조를 따릅니다. Folio는 파일을 옮기거나 지우기 전에 사용자의 확인을 받고, 옮긴 기록을 `.folio/moves.jsonl`에 남겨 되돌릴 수 있게 합니다.
- 앱과 명령줄 도구는 같은 액션 구현(`FolioActions`)을 거쳐 데이터를 바꿉니다.

## 요구 사항

- macOS 26 이상, iPadOS 26 이상
- Xcode 27 이상(Swift 6.4)
- [mise](https://mise.jdx.dev): 빌드 명령과 XcodeGen 버전을 정합니다.
- Node.js: 노트 편집기와 수식 번들(`web/`)을 다시 만들 때만 필요합니다. 빌드한 번들은 저장소에 들어 있습니다.

## 빌드와 실행

Xcode 프로젝트는 `project.yml`에서 생성합니다.

```bash
mise run generate
open Folio.xcodeproj
```

빌드와 테스트 작업은 모두 `mise.toml`에 정의되어 있습니다.

| 명령 | 설명 |
| --- | --- |
| `mise run test` | 모든 패키지 테스트와 디자인 토큰 검사 |
| `mise run build-mac` | macOS 앱 빌드 |
| `mise run build-ipad` | iPad 시뮬레이터용 빌드 |
| `mise run build-web` | `web/`의 노트 편집기와 수식 번들 생성(`app/resources/web`) |
| `mise run install-mac` | Release 빌드를 `/Applications/Folio.app`에 설치 |
| `mise run fixture -- <폴더>` | 가짜 학업 폴더 생성 |
| `mise run cli -- <명령>` | 명령줄 도구 실행 |
| `mise run install-cli` | 명령줄 도구를 `~/.local/bin`에 설치 |

### 가짜 학업 폴더

실제 학업 폴더를 건드리지 않고 앱을 써 보려면, 가짜 폴더를 만든 뒤 그 경로를 `FOLIO_GIST` 환경 변수로 넘깁니다.

```bash
mise run fixture -- ~/folio-demo
open -n --env FOLIO_GIST=$HOME/folio-demo <빌드한 Folio.app 경로>
```

## 명령줄 도구

`mise run install-cli`로 설치하면 어디서나 `folio`를 쓸 수 있습니다. 명령은 `<대상> <동작>` 형식입니다.

```bash
folio help
folio help "과제 추가"
folio assignment add EC4207 "HW 3" --due "2026-11-04 23:59" --dry-run
```

- `folio help <하고 싶은 일>`은 자연어로 명령을 찾아 줍니다.
- 쓰기 명령은 모두 `--dry-run`으로 결과를 먼저 볼 수 있습니다. `--json`을 붙이면 프로그램이 읽을 수 있는 JSON으로 출력합니다.
- 대상 학업 폴더는 `--gist <경로>`, `FOLIO_GIST`, 앱에서 연 폴더 순서로 정합니다.
- AI 에이전트용 스킬은 `folio skill --install <스킬 폴더>`로 설치합니다.

## 저장소 구조

```text
app/               SwiftUI 앱(macOS, iPadOS)
packages/
  folio-core/      모델, 저장소, 액션, 검색 색인, 명령줄 도구, 테스트용 가짜 폴더
  folio-markdown/  마크다운 파서와 확장 문법, HTML 렌더러
  folio-ai/        Claude 연동 계층
web/               노트 편집기(CodeMirror)와 수식(KaTeX, AsciiMath) 번들 원본
docs/              명세와 디자인 시스템
scripts/           디자인 토큰 검사
```

플랫폼과 무관한 로직은 Swift 패키지에 있어서, Xcode 없이 `swift test`로 테스트할 수 있습니다.

## 문서

- [docs/SPEC.md](docs/SPEC.md): 기능 명세. 화면, 데이터 모델, 계산 규칙, 명령줄 도구
- [docs/DESIGN.md](docs/DESIGN.md): 디자인 시스템. 원칙, 토큰, 구성 요소, 창 구조
- [AGENTS.md](AGENTS.md): 구현 규칙. 모듈 경계, 데이터 원칙, 테스트 기준
