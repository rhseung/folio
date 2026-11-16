import ArgumentParser
import FolioActions

// 액션 하나를 만들어 쓰는 손 명령이다. MCP의 `--propose`는 이 명령을 쓰기로 보고, 만든 액션을 제안한다.
protocol BuildsAction: ParsableCommand {
    static var builds: any Action.Type { get }
}
