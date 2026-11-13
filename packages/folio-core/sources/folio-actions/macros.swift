/// Declares an action: its command, help and texts, with the struct's stored properties as its inputs. Writes the
/// memberwise init, the JSON coding (defaults, `@New` ids, `Patch` keys), `spec` and the `Action` conformance.
/// `{field}` in `confirm` and `done` is filled with the field's value, or the name of what it points at.
@attached(member, names: named(init), named(CodingKeys), named(encode), named(spec), named(command))
@attached(extension, conformances: Action)
public macro Action(
    _ command: String, _ summary: String, discussion: String = "", effect: Effect = .changes, confirm: String? = nil, done: String,
    examples: [String] = [], phrases: [String] = [], cli: CLIMode = .generated, undoable: Bool = false
) = #externalMacro(module: "FolioMacros", type: "ActionMacro")

/// How the action gets its CLI command. `.manual(reason:)` says why the generator can't write it; `folio actions
/// --check` fails on a hand-written command without a reason, so each one stays a decision rather than a habit.
public enum CLIMode: Sendable {
    case generated, manual
    public static func manual(reason: String) -> CLIMode { .manual }
}

/// A positional CLI argument; other fields of an action are options.
@attached(peer) public macro Arg() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
/// The id of the item the action creates: hidden on the CLI, made when left out, and reported as `made`.
@attached(peer) public macro New() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
/// A Bool that defaults to true, set false by a flag (`--off`, or the name given).
@attached(peer) public macro Off(_ flag: String = "off") = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
/// Kept out of the CLI and help; still part of the JSON input.
@attached(peer) public macro Hidden() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
/// The CLI's name for the field when it isn't the field's own: `--unit` given again for each of `units`.
@attached(peer) public macro CLIName(_ name: String) = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
/// On the CLI, a path to a file holding the value: the text of a `String`, any other type decoded from JSON.
/// `-` reads standard input. With `perItem`, a list takes one file per item, given as several arguments.
@attached(peer) public macro FromFile(_ valueName: String = "file", perItem: Bool = false) =
    #externalMacro(module: "FolioMacros", type: "MarkerMacro")
/// A folder on this Mac: the CLI takes it relative to where it runs and passes it on absolute.
@attached(peer) public macro Folder() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
/// On the CLI, text the CLI reads into the value (each item of a list), such as `05_Matchings.pdf:3-12`: the type
/// conforms to FolioCLI's `CLIText`, which also looks up the names in it. `form` is added to the CLI's help only,
/// since the JSON input takes the value itself.
@attached(peer) public macro Parsed(_ valueName: String, _ form: String) = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
