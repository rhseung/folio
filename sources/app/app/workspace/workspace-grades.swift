import FolioDomain
import Foundation

extension Workspace {

    var requirementCatalog: Catalog { catalog.scoped(to: transcript.graduation.programs) }

    // mailto는 보내는 계정을 고를 수 없고, 메일 앱의 기본 계정이 보낸다.
    func mailURL(to address: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = address
        return address.isEmpty ? nil : c.url
    }
}
