// 버전은 이 한 곳에서만 정한다. `mise run version-bump`가 아래 줄을 고쳐 쓰고, `mise run generate`가 이 값을
// 앱의 MARKETING_VERSION에 복사하며, 릴리스 워크플로는 이 값과 다른 태그를 거절한다. 빌드 번호는 빌드만 아는
// 커밋 수이므로 여기에 두지 않는다(scripts/version.sh).
public enum FolioVersion {
    public static let marketing = "0.1.0"
}
