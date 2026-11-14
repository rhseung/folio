import ArgumentParser

// 읽기 선언(`@Query`)으로 옮길 수 없는 손 읽기 명령이다. 이유가 비면 `actions --check`가 실패한다. MCP 서버는 이 명령을
// 도구로 열 때 패널에 열지와 `--propose`의 사본에서 읽을지를 여기서 읽는다.
protocol HandRead: ParsableCommand {
    static var reason: String { get }
    static var panel: Bool { get }
    // 사본에는 `--propose`가 쌓은 제안이 있다. 사본에 없는 것(이 기기의 색인)을 읽는 명령만 끈다.
    static var staged: Bool { get }
}

extension HandRead {
    static var panel: Bool { false }
    static var staged: Bool { true }
}
