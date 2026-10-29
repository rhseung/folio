/// Declares an action: its command, help and texts, with the struct's stored properties as its inputs. Writes the
/// memberwise init, the JSON coding (defaults, `@New` ids, `Patch` keys), `spec` and the `Action` conformance.
/// `{field}` in `confirm` and `done` is filled with the field's value, or the name of what it points at.
@attached(member, names: named(init), named(CodingKeys), named(encode), named(spec), named(command))
@attached(extension, conformances: Action)
public macro Action(_ command: String, _ summary: String, discussion: String = "", effect: Effect = .changes, confirm: String? = nil, done: String,
                    examples: [String] = [], phrases: [String] = [], cli: CLIMode = .generated)
    = #externalMacro(module: "FolioMacros", type: "ActionMacro")

public enum CLIMode: Sendable { case generated, manual }

/// A positional CLI argument; other fields of an action are options.
@attached(peer) public macro Arg() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
/// The id of the item the action creates: hidden on the CLI, made when left out, and reported as `made`.
@attached(peer) public macro New() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
/// A Bool that defaults to true, set false by a flag (`--off`, or the name given).
@attached(peer) public macro Off(_ flag: String = "off") = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
/// Kept out of the CLI and help; still part of the JSON input.
@attached(peer) public macro Hidden() = #externalMacro(module: "FolioMacros", type: "MarkerMacro")
