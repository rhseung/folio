// 버전의 원본은 `v<X.Y.Z>` 태그이고, 이 값은 개발 빌드의 자리표시값이다. 릴리스 빌드(release.yml, install-release)는
// 빌드하기 전에 `folio-dev version stamp`로 태그의 버전을 써넣고 커밋하지 않는다. PR마다 이 상수를 올리면 동시에 열린
// PR끼리 충돌하기 때문이다. `mise run generate`가 이 파일만 Swift 인터프리터로 읽어 앱의 MARKETING_VERSION에 복사하므로
// 이 파일은 다른 파일에 기대지 않는다. 빌드 번호는 빌드만 아는 커밋 수이므로 여기에 두지 않는다.
public enum FolioVersion {
    public static let marketing = "0.0.0"
}
