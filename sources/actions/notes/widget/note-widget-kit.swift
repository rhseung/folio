import FolioDomain
import Foundation

// 위젯 frame에 위젯 스크립트보다 먼저 넣는 것이다. 그림 스타일의 CSS 변수와 화살촉, 기본 컨트롤 스타일, 수식
// 렌더러(글 속은 KaTeX, SVG 라벨은 MathJax path)를 넣는다(sources/web/src/widget.js). 위젯은 바깥 파일을 불러오지 못해서 앱과
// CLI의 그려 보기가 함께 넣는다.
public enum NoteWidgetKit {
    public static let script: String = {
        let kit =
            Bundle.module.url(forResource: "widget-kit", withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return "{ const s = document.createElement('style'); s.id = 'folio-figure-style'; s.textContent = \(js(FigureStyle.variables)); "
            + "document.documentElement.prepend(s) }\n" + markersScript + "\n" + kit
    }()

    // 촉은 body를 다 읽은 뒤 html의 마지막 자식으로 둔다. 문서 순서로 위젯의 요소보다 뒤에 있어야 위젯의
    // `document.querySelector('svg')`가 위젯 자신의 그림을 찾고, body 밖이라 위젯이 `body.innerHTML`을 바꿔도 남는다.
    // 문서를 읽기 전에 html에 넣으면 파서가 head와 body를 그 뒤에 붙인다. html에 `insertAdjacentHTML`을 쓰면 파서가
    // html을 context로 읽어 빈 head와 두 번째 body를 만들므로, template에서 읽은 뒤 붙인다.
    static let markersScript =
        "{ const add = () => { const t = document.createElement('template'); t.innerHTML = \(js(FigureStyle.widgetMarkers)); "
        + "document.documentElement.append(t.content) }; "
        + "if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', add); else add() }"

    static func js(_ text: String) -> String {
        (try? JSONEncoder().encode(text)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "''"
    }
}
