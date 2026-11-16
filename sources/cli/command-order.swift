import ArgumentParser

// 하위 명령은 폴더에서 만든 목록이라 손으로 정한 차례가 없다. 도움말에는 이름 차례로 보인다.
func alphabetical(_ commands: [any ParsableCommand.Type]) -> [any ParsableCommand.Type] {
    commands.sorted { $0._commandName < $1._commandName }
}
