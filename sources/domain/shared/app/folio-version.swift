// 버전은 이 한 곳에서만 정한다. `mise run version-bump`(folio-dev)가 아래 리터럴을 고쳐 쓰고, `mise run generate`가
// 이 파일만 Swift 인터프리터로 읽어 앱의 MARKETING_VERSION에 복사하므로 이 파일은 다른 파일에 기대지 않는다. 릴리스
// 워크플로는 이 값과 다른 태그를 거절한다. 빌드 번호는 빌드만 아는 커밋 수이므로 여기에 두지 않는다.
public enum FolioVersion {
    public static let marketing = "0.1.0"
}
