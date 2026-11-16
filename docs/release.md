# 버전과 릴리스

버전을 올리거나 릴리스를 만들 때 읽는다. 작업은 `mise run release-notes`, `release-tag`, `release-past`, `install-release`이고, 규칙은 `folio-dev`(`sources/tools/dev`)에 있다.

## 버전

- 버전의 원본은 `main`의 `v<X.Y.Z>` 태그다. 어느 커밋의 버전은 그 커밋에 닿는 가장 높은 태그다(`folio-dev version get`). PR마다 상수를 올리면 동시에 열린 PR끼리 충돌하므로 버전을 파일에 두지 않는다.
- 커밋한 `FolioVersion.marketing`은 개발 빌드의 자리표시값(`0.0.0`)이다. 릴리스 빌드(`release.yml`, `install-release`)만 빌드하기 전에 `folio-dev version stamp`로 태그의 버전을 써넣고, 그 변경은 커밋하지 않는다. 앱의 `MARKETING_VERSION`은 `mise run generate`가 이 상수에서 읽어 `.build/version.xcconfig`에 쓰고, CLI(`folio --version`)와 MCP는 이 상수를 그대로 쓴다.
- 빌드 번호는 커밋 수(`git rev-list --count HEAD`)라 파일에 두지 않는다. `main`이 스쿼시 머지뿐이라 머지할 때마다 는다.
- **patch는 PR마다 올린다.** `## 패치 노트` 절에 항목이 있는 PR이 머지되면 다음 patch를 릴리스한다. `feat`가 있어도 patch다. 패치 노트가 없는 PR(리팩터, CI, 문서)은 릴리스하지 않고, 다음 릴리스가 그 PR까지 담는다.
- **minor는 기능 묶음이 끝날 때 올린다.** 묶음은 Project의 상위 이슈 순서와 매니저의 작업 순서를 따른다(예: LMS 전부, 탭 끌기와 단축키, 공부 시스템 1단계). 묶음이 끝나면 매니저가 minor를 제안하고, 사용자가 승인하면 그 묶음의 마지막 PR이나 다음으로 머지할 PR에 `release/minor` 라벨을 붙인다. 그 PR이 머지되면 patch 대신 다음 minor(`0.5.4` 다음 `0.6.0`)를 릴리스한다. 머지할 PR이 없으면 `mise run release-tag -- minor`로 바로 낸다.
- major는 사용자 데이터 형식과 기능 범위를 굳히는 1.0에만 올린다(`mise run release-tag -- major`, 사용자 승인 뒤).

## 릴리스 노트

- 원본은 PR 본문의 `## 패치 노트` 절이다(#415, AGENTS.md "PR 전 점검"). 릴리스 본문은 앞 버전의 태그 뒤 머지된 PR의 본문을 릴리스할 때 읽으므로 머지 뒤에 고친 본문도 들어간다. 저장소에는 버전별 노트 파일을 두지 않는다. `mise run release-notes`가 다음 버전과 그 본문을 미리 보인다.
- 스쿼시 커밋은 PR 제목과 PR 본문의 `## 패치 노트` 절만 남긴다. 매니저가 자동 머지를 걸 때 커밋 본문을 정한다(AGENTS.md "이슈와 작업 순서").
- 릴리스 본문은 `## 패치 노트` 제목, 형식 표시(`<!-- folio-patch-notes 2 -->`), 그 버전의 날짜(`<!-- folio-released <ISO 8601> -->`), 종류별 소제목(`### feat`, `### fix`, `### change` 순)으로 묶은 항목 줄, 머지된 PR 목록, 설치 안내 순이다. 본문을 쓰는 일(`PatchNotes.releaseBody`)과 앱이 GitHub Releases API에서 받아 읽는 일(`PatchNotes.releases`)이 `PatchNotes` 한 타입에 있고 `swift test`가 왕복을 검사한다. 줄의 형식을 바꾸면 `PatchNotes.format`을 올린다.
- 버전의 날짜는 그 버전의 마지막 커밋(스쿼시 머지 커밋)의 시각이다. GitHub 릴리스의 게시일은 과거로 돌릴 수 없어서 본문에 적고, 앱은 본문의 날짜를, 없으면 게시일을 보인다. 태그의 시각도 그 커밋의 시각으로 단다.
- 앞 버전은 커밋이 아니라 버전으로 고른다(`ReleasePlan.previous`). 같은 커밋에 patch와 minor 태그가 함께 있어도 노트가 겹치지 않는다. 첫 릴리스(앞선 태그 없음)는 그때까지 머지된 모든 PR을 모은다.

## 릴리스

- `release.yml`은 `main` push마다 두 작업으로 돈다. `plan`(`folio-dev release plan`)이 그 커밋에 닿는 태그 중 게시되지 않은 것과, 지난 태그 뒤의 PR에 패치 노트가 있으면 다음 버전을 고른다. `release`가 고른 버전마다 하나씩 그 커밋을 빌드하고 `Folio-<버전>.zip`과 본문을 만든 뒤, 게시 바로 앞에서 태그(그 커밋의 시각)를 달고 GitHub Release를 게시한다.
- 태그를 빌드 뒤에 달므로 빌드가 실패한 실행은 태그 없이 끝나고, 다시 돌리면 같은 버전을 다시 만든다. 태그를 단 뒤 게시하기 전에 멈춘 실행과, 사람이 푸시한 태그(`release-tag`)의 실행이 대기 중에 새 실행에 밀려 취소된 경우는 다음 실행의 `plan`이 게시되지 않은 태그로 찾아 먼저 게시한다. 실행은 하나씩 돈다. 수동 실행(`workflow_dispatch`)도 같은 일을 하므로 밀린 릴리스를 바로 게시할 때 쓴다.
- Developer ID 서명, 공증, 자동 업데이트(#414)는 아직 없다.

## 지난 버전 나누기

- 버전을 PR마다 올리기 전에 머지된 PR은 `mise run release-past -- <버전> <커밋>`으로 나눈다. 그 커밋에 커밋 시각의 태그를 달고, 앱 없이 노트만 있는 릴리스를 게시한다. 그 커밋의 코드 버전은 태그와 다르므로 빌드하지 않는다. `--dry-run`으로 태그와 본문을 먼저 보고, 낮은 버전부터 차례로 단다. 태그를 달거나 릴리스를 게시하기 전에 사용자 승인을 받는다.
- 0.1.0 뒤의 PR 44개는 머지 순서대로 넷으로 나눈다(#521). 0.2.0은 #449까지(칸 배치 기억과 이름 붙인 배치, 툴바 녹음 캡슐, 항목 메뉴, MCP로 모든 액션), 0.3.0은 #467까지(Claude로 렉처 나누기, 패널의 그림·위젯과 PDF·녹음 읽기, 칸 개수 제한 없앰, `.tex` 빌드), 0.4.0은 #480까지(첫 실행 화면, iPad 틀과 iPhone, LMS 제안함)이고, 0.5.0은 그 뒤 #521까지를 `release/minor` 라벨로 정상 절차에 따라 빌드해 게시한다.

## 설치

- `install-release [-- <ref>]`는 `origin/main`(또는 준 커밋)을 임시 워크트리에 꺼내 그 커밋의 태그 버전을 써넣고 Release로 빌드한 뒤, `/Applications/Folio.app`과 `~/.local/bin/folio`를 바꾸고 워크트리를 지운다. 커밋하지 않은 작업과 다른 세션의 워크트리는 들어가지 않는다. 실행 중인 `/Applications/Folio.app`만 끄고, 같은 번들 ID의 Debug 앱은 건드리지 않는다.
- 지금 체크아웃을 그대로 설치하는 `install-mac`과 Xcode에서 바로 빌드한 앱은 버전이 자리표시값(`0.0.0`)이다. 새 기능 화면은 지금 버전까지의 릴리스만 보이므로 이 빌드에서는 늘 비어 있고, 고장이 아니다. 화면을 확인할 때는 `Workspace.scenario`의 견본 릴리스로 그린다(`mise run render`).
