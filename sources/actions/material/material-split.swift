import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material split", "렉처 파일을 단원 구간으로 나누기. 그 파일의 단원 구간을 모두 이 목록으로 바꾸고, 없는 단원은 만든다",
    done: "{material}을(를) 단원 구간으로 나눴습니다",
    examples: [#"folio material split EC4207/05_Matchings.pdf 1-4:매칭 5-8:König 9-13:"Hall의 결혼 정리""#],
    phrases: ["단원으로 나누기", "렉처 목차 나누기", "렉처를 단원별로"], cli: .manual(reason: "<쪽>:<단원> 인자를 구간으로 읽고, 없는 단원 이름은 새 단원으로 만든다"))
public struct MaterialSplit {
    @Arg var course: Course.ID
    @Arg var material: Material.ID
    var sections: [LectureCut]

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            try checkCuts(sections, in: f)
            f.split(material, into: sections, device: ctx.device, now: ctx.now)
        }
    }
}
