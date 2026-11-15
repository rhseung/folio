# CI

`ci.yml`과 검사 경로, 빌드 캐시를 고칠 때 읽는다. 머지 규칙은 AGENTS.md "이슈와 작업 순서"에 있다.

- PR 작업은 Linux의 `pick checks`와 macOS의 `packages`(`mise run test`), `mac app`(`mise run test-app`), `ipad app`(`mise run build-ipad-tests`, 필요하면 `test-ipad`) 셋이다. Release iPad 빌드(`ipad release`)는 main push에서만 돈다. main push는 모든 검사를 돌린다.
- macOS 러너는 동시 실행 수가 정해져 있어 PR이 여럿이면 줄을 선다(#385). 그래서 macOS 작업을 늘리지 않는다. `mac app`은 노트 보기와 나머지를 나누지 않고 한 번에 돌린다. 나누면 같은 Debug 앱을 두 러너가 따로 빌드하기 때문이다.
- PR이 바꾼 파일이 닿지 않는 검사는 건너뛴다(룰셋에는 통과다). 어떤 파일이 어느 검사에 닿는지는 `.github/check-paths.yml`의 glob 목록이고 `pick checks`가 `dorny/paths-filter`로 읽는다. 이름을 바꾼 파일은 옛 경로도 세고, 파일이 3000개 이상이면 모두 돌린다. `ipad app`의 시뮬레이터 테스트는 그 테스트가 읽는 코드(`ipad-simulator` 필터)가 바뀐 PR과 main push에서만 돌고, 시뮬레이터는 빌드하는 동안 미리 켠다(`scripts/ipad-simulator.sh boot`).
- 작업은 main push가 남긴 빌드 캐시(Xcode 작업은 DerivedData, `packages`는 패키지의 `.build`)에서 시작한다. Xcode 준비 단계는 `.github/actions/xcode-setup` 하나다. 체크아웃이 모든 파일의 시각을 새로 찍으므로 CI는 파일 시각을 내용(blob 해시)에서 정해, 캐시된 빌드가 바뀐 파일만 다시 컴파일하게 한다. 커밋하지 않는 프로젝트의 `Package.resolved`는 커밋한 `Package.resolved`와 `project.yml`이 같은 캐시에서만 받아 패키지 해석을 건너뛰고, 다르거나 main push면 새로 해석한다.
- CI에는 lint 작업을 따로 두지 않는다. 훅이 돌지 않는 커밋(`--no-verify`, 충돌 없는 머지 커밋, GitHub가 만든 스쿼시 커밋)과 각자는 통과한 두 PR을 합친 결과(폴더의 Swift 파일 수, 기준선, import 순서)는 `packages`의 `mise run test`가 잡는다. 이 작업은 빌드가 필요 없는 SwiftLint와 swift-format 검사를 맨 앞에서 돌린다.
- 리뷰 승인은 `review.yml`이 정한다. 문서(`docs/`, 최상위 `*.md`, `.github/**/*.md`)만 바뀐 PR은 Actions가 승인하고, 그 밖은 리뷰 봇이 리뷰한다(판단은 `check-paths.yml`의 `code` 필터).
- `quality.yml`은 매주와 설정을 바꾼 PR에서 `periphery`와 `analyze`를 돌려 실행 요약에 적고 실패로 치지 않는다. 이름으로만 닿는 코드가 있어 사람이 보고 지운다.
- `accessibility.yml`은 매일 밤 main에서, 그리고 `a11y` 라벨이 붙은 PR에서 `test-a11y`를 돌린다. 룰셋의 필수 검사가 아니다. 아직 고치지 못한 결과는 `tests/e2e/app`의 `KnownFindings`에 화면, 종류, 요소로 적고 #471 체크리스트에 남긴다. 모든 결과를 통과시키는 처리기를 두지 않는다.
