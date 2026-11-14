import FolioDomain

@attached(member, names: named(init), named(CodingKeys), named(encode), named(spec), named(command), named(currentFile))
@attached(extension, conformances: Action)
public macro Action(
    _ command: String, _ summary: String, discussion: String = "", effect: Effect = .changes, confirm: String? = nil, done: String,
    examples: [String] = [], phrases: [String] = [], cli: CLIMode = .generated, undoable: Bool = false,
    proposal: ProposalTarget.Effect? = nil, panel: Bool = false
) = #externalMacro(module: "FolioMacros", type: "ActionMacro")

@attached(member, names: named(init), named(CodingKeys), named(encode), named(spec), named(command))
@attached(extension, conformances: Query)
public macro Query(
    _ command: String, _ summary: String, discussion: String = "", examples: [String] = [], phrases: [String] = [],
    cli: CLIMode = .generated, panel: Bool = false, lines: Bool = false, grades: Bool = false
) = #externalMacro(module: "FolioMacros", type: "QueryMacro")

@attached(peer) public macro Arg() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro New() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro Off(_ flag: String = "off") = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro Hidden() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro CLIName(_ name: String) = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro FromFile(_ valueName: String = "file", perItem: Bool = false) =
    #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro Folder() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro Parsed(_ valueName: String, _ form: String) = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
// 액션 입력의 이 필드는 문서 하나 전체이고, JSON 입력은 지금 문서 위에 덮는다(`folio run`, MCP). 파일 전체의 디코더가
// 빠진 키를 기본값으로 채우므로, 덮지 않으면 `{"settings":{}}`가 모든 설정을 되돌린다.
@attached(peer) public macro WholeFile() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
