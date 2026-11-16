import FolioActions
import FolioCore
import FolioDomain
import Foundation

// 필드의 Swift 형식만으로는 입력 형식이 다 드러나지 않는 액션이 형식을 더 좁힌다. 예를 들어 `settings set`의 필드는
// 글이지만 선언된 설정 이름만 받는다.
protocol InputRefining {
    static func refine(_ input: JSONValue) -> JSONValue
}
