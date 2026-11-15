# 버전과 릴리스

버전을 올리거나 릴리스를 만들 때 읽는다. 작업은 `mise run version-bump`, `release-notes`, `release-tag`, `install-release`이고, 규칙은 `folio-dev`(`sources/dev`)에 있다.

## 버전

- 버전은 `FolioVersion.marketing`(`X.Y.Z`)에서만 정한다. 앱의 `MARKETING_VERSION`은 `mise run generate`가 여기서 읽어 `.build/version.xcconfig`에 쓰고, CLI(`folio --version`)와 MCP는 이 상수를 그대로 쓴다. 커밋한 뒤 Xcode에서 빌드하면 빌드 번호는 마지막 `generate` 때의 것이다.
- 빌드 번호는 커밋 수(`git rev-list --count HEAD`)라 파일에 두지 않는다. `main`이 스쿼시 머지뿐이라 머지할 때마다 는다.
- 1.0 전에는 새 기능이 든 릴리스는 minor, 고침만 든 릴리스는 patch를 올린다. major는 사용자 데이터 형식과 기능 범위를 굳히는 1.0에만 올린다. 올린 커밋은 PR로 머지한다.

## 릴리스 노트

- 원본은 PR 본문의 `## 패치 노트` 절이다(#415, AGENTS.md "PR 전 점검"). `release-notes`가 지난 태그 뒤 머지된 PR의 본문을 읽으므로 머지 뒤에 고친 본문도 들어간다. 저장소에는 버전별 노트 파일을 두지 않는다.
- 릴리스 본문은 `## 패치 노트` 제목, 형식 표시(`<!-- folio-patch-notes 1 -->`), 종류별 소제목(`### feat`, `### fix`, `### change` 순)으로 묶은 항목 줄, 머지된 PR 목록, 설치 안내 순이다. 본문을 쓰는 일(`PatchNotes.releaseBody`)과 앱이 GitHub Releases API에서 받아 읽는 일(`PatchNotes.items`)이 `PatchNotes` 한 타입에 있고 `swift test`가 왕복을 검사한다. 줄의 형식을 바꾸면 `PatchNotes.format`을 올린다.
- 첫 릴리스(앞선 태그 없음)는 그때까지 머지된 모든 PR을 모은다.

## 릴리스

- `release-tag`가 `origin/main`에 `v<버전>` 태그를 달고 푸시하면 `release.yml`이 Release 앱을 빌드해 `Folio-<버전>.zip`을 붙인 GitHub Release 초안을 만든다. 태그와 `FolioVersion`이 다르면 실패한다. 수동 실행(`workflow_dispatch`, `since` 입력)은 릴리스 없이 같은 결과를 아티팩트로만 올린다.
- 초안은 사람이 확인하고 게시한다. 게시해야 앱이 그 버전의 패치 노트를 본다.
- Developer ID 서명, 공증, 자동 업데이트(#414)는 아직 없다.

## 설치

- `install-release [-- <ref>]`는 `origin/main`(또는 준 커밋)을 임시 워크트리에 꺼내 Release로 빌드하고, `/Applications/Folio.app`과 `~/.local/bin/folio`를 바꾼 뒤 워크트리를 지운다. 커밋하지 않은 작업과 다른 세션의 워크트리는 들어가지 않는다. 실행 중인 `/Applications/Folio.app`만 끄고, 같은 번들 ID의 Debug 앱은 건드리지 않는다.
- 지금 체크아웃을 그대로 설치하는 `install-mac`은 그 안에서 쓰는 단계다.
