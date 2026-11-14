import Foundation

enum Shell {
    // 명령은 저장소 맨 위에서 돈다. mise 작업과 워크플로가 모두 그 폴더에서 부르기 때문이다.
    @discardableResult
    static func run(_ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DevError("\(arguments.joined(separator: " ")) failed with status \(process.terminationStatus)")
        }
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
