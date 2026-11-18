import FolioDomain
import Foundation

// 위젯 frame에 위젯 스크립트보다 먼저 넣는 것이다. 그림 스타일의 CSS 변수, 기본 컨트롤 스타일, 수식 렌더러(글 속은 KaTeX, SVG 라벨은 MathJax path)를
// 넣는다(sources/web/src/widget.js). 위젯은 바깥 파일을 불러오지 못해서 앱과 CLI의 그려 보기가 함께 넣는다.
public enum NoteWidgetKit {
    public static let script: String = {
        let variables = (try? JSONEncoder().encode(FigureStyle.variables)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "''"
        let kit =
            Bundle.module.url(forResource: "widget-kit", withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return "{ const s = document.createElement('style'); s.id = 'folio-figure-style'; s.textContent = \(variables); "
            + "document.documentElement.prepend(s) }\n" + kit
    }()
}
