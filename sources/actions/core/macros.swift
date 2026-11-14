@attached(member, names: named(init), named(CodingKeys), named(encode), named(spec), named(command))
@attached(extension, conformances: Action)
public macro Action(
    _ command: String, _ summary: String, discussion: String = "", effect: Effect = .changes, confirm: String? = nil, done: String,
    examples: [String] = [], phrases: [String] = [], cli: CLIMode = .generated, undoable: Bool = false
) = #externalMacro(module: "FolioMacros", type: "ActionMacro")

@attached(peer) public macro Arg() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro New() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro Off(_ flag: String = "off") = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro Hidden() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro CLIName(_ name: String) = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro FromFile(_ valueName: String = "file", perItem: Bool = false) =
    #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro Folder() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
@attached(peer) public macro Parsed(_ valueName: String, _ form: String) = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
