struct DeclaredAction {
    var name: String
    // sources/actions 기준의 파일 경로. 생성한 명령이 sources/cli/generated의 같은 자리에 간다.
    var path: String
    var condition: String?
}
