# TeX 엔진 Tectonic

`.tex` 빌드와 Tectonic 라이브러리를 고칠 때 읽는다.

- iPadOS는 앱이 다른 프로그램을 띄우지 못하게 한다. 그래서 Mac과 iPad 모두 Tectonic을 정적 라이브러리(`FolioTectonic.xcframework`)로 앱 안에 넣는다.
- 라이브러리는 커밋하지 않는다. `tectonic.yml` 워크플로가 `sources/tectonic`(브리지 crate `bridge/`, Tectonic 패치 `patches/`, `build.sh`)에서 빌드해 프리릴리스 자산으로 올리고, `mise run tectonic`(`sources/tectonic/fetch.sh`)이 `sources/tectonic/pin.json`의 sha256으로 확인해 `sources/tectonic/vendor`에 받는다.
- Swift 패키지를 읽는 모든 작업(`generate`, `test`, `check-code`, `cli`, `gen-cli`, `fixture`, `install-cli`)이 먼저 `tectonic`을 돌린다. SwiftPM은 `Package.swift`를 읽을 때마다 바이너리 타깃의 폴더를 보기 때문이다.
- `bridge`, `patches`, `build.sh`, 도구 판을 정하는 `tectonic.yml`을 바꾸면 `tectonic.yml`이 그 내용의 해시로 이름 지은 프리릴리스(`tectonic-<판>-<해시>`)를 만들고 새 `pin.json`을 작업 요약에 적는다. 그것을 커밋한다. 핀이 지금 입력과 다르면 `mise run tectonic`이 경고한다.
- Tectonic 자체를 고친 부분은 `patches/`의 패치로 두고 빌드할 때 적용한다: iOS에서 CoreText로 글꼴 찾기, 한 프로세스에서 빌드를 거듭할 때 중단된 xdvipdfmx가 남긴 전역 상태 되돌리기.
- 빌드는 Mac의 `tectonic -X compile -Z continue-on-errors --synctex`와 같다. 받은 패키지만으로 먼저 빌드해 보고, 없는 파일이 있을 때만 온라인으로 다시 빌드한다.
- TeX 패키지와 서식은 데이터라 앱이 Tectonic의 번들 서버에서 받아 `Caches/Tectonic`에 둔다. Mac에서는 Homebrew Tectonic과 같은 폴더다.
