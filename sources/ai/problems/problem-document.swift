import Foundation

// 문제지나 해설 파일 하나다. PDF는 쪽 그림과 글을 함께 읽게 그대로 보내고, `.tex` 원본은 글로 보낸다.
public enum ProblemDocument: Sendable, Equatable {
    case pdf(Data)
    case tex(String)

    func blocks(_ label: String) -> [ContentBlock] {
        switch self {
        case .pdf(let data): [.text("\(label):"), .pdf(data)]
        case .tex(let source): [.text("\(label) (LaTeX source; \"page\" is null):\n<latex>\n\(source)\n</latex>")]
        }
    }
}
