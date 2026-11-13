import FolioDomain
import FolioMarkdown
import Foundation
import Observation

/// The input guide (#395): the edit view's typing help by situation, read from the tables the editor reads with the
/// snippets of `syntax` from settings, narrowed by a tab and a search.
@MainActor @Observable
final class InputGuideModel {
    let syntax: MathSyntax
    /// Nil is every section.
    var section: InputGuide.Section?
    var search = ""
    private let entries: [InputGuide.Entry]

    init(workspace: Workspace, syntax: MathSyntax) {
        self.syntax = syntax
        // The iPad has no completion menu yet, nor a table menu (#31): it is left out rather than shown as keys that
        // do nothing there.
        #if os(macOS)
        let menus = true
        #else
        let menus = false
        #endif
        entries = InputGuide.entries(catalog: NoteAssist(settings: workspace.settings).catalog(syntax: syntax), menus: menus, tableMenu: menus)
    }

    /// The tabs: every section, then each one with something in it.
    var tabs: [(InputGuide.Section?, String)] {
        [(nil, String(localized: .notesGuideAll))] + InputGuide.grouped(entries).map { (Optional($0.section), $0.section.label) }
    }

    var shown: [(section: InputGuide.Section, entries: [InputGuide.Entry])] {
        InputGuide.grouped(InputGuide.filter(entries.filter { section == nil || $0.section == section }, search, words: Self.words))
    }

    static func words(_ words: InputGuide.Words) -> String {
        switch words {
        case .phrase(let phrase): phrase.label
        case .table(let command): TableCommands.title(command)
        case .named(let text), .code(let text): text
        case .list(let names): InputGuide.listed(names)
        }
    }
}

extension InputGuide.Section {
    var label: String {
        switch self {
        case .menu: String(localized: .notesGuideSectionMenu)
        case .tab: String(localized: .notesGuideSectionTab)
        case .auto: String(localized: .notesGuideSectionAuto)
        case .table: String(localized: .notesGuideSectionTable)
        }
    }
}

extension InputGuide.Phrase {
    var label: String {
        switch self {
        case .blocks: String(localized: .notesGuideBlocks)
        case .link: String(localized: .notesGuideLink)
        case .headingLink: String(localized: .notesGuideHeadingLink)
        case .pageLink: String(localized: .notesGuidePageLink)
        case .embed: String(localized: .notesGuideEmbed)
        case .calloutKind: String(localized: .notesGuideCalloutKind)
        case .codeLanguage: String(localized: .notesGuideCodeLanguage)
        case .mathSymbols: String(localized: .notesGuideMathSymbols)
        case .texEnvironment: String(localized: .notesGuideTexEnvironment)
        case .asciiMathSymbol: String(localized: .notesGuideAsciiMathSymbol)
        case .nextSlot: String(localized: .notesGuideNextSlot)
        case .indent: String(localized: .notesGuideIndent)
        case .pairs: String(localized: .notesGuidePairs)
        case .wrap: String(localized: .notesGuideWrap)
        case .listContinue: String(localized: .notesGuideListContinue)
        case .listEnd: String(localized: .notesGuideListEnd)
        case .tableMenu: String(localized: .notesGuideTableMenu)
        case .linkTargets: String(localized: .notesGuideLinkTargets)
        case .lastPageFirst: String(localized: .notesGuideLastPageFirst)
        case .embedTargets: String(localized: .notesGuideEmbedTargets)
        case .inMath: String(localized: .notesGuideInMath)
        case .endWritten: String(localized: .notesGuideEndWritten)
        case .fromTwoLetters: String(localized: .notesGuideFromTwoLetters)
        case .snippet: String(localized: .notesGuideSnippet)
        case .mathSnippet: String(localized: .notesGuideMathSnippet)
        case .previousSlot: String(localized: .notesGuidePreviousSlot)
        case .renumbers: String(localized: .notesGuideRenumbers)
        case .nestedStepsOut: String(localized: .notesGuideNestedStepsOut)
        case .inTable: String(localized: .notesGuideInTable)
        case .blockList: String(localized: .notesGuideBlockList)
        case .targetList: String(localized: .notesGuideTargetList)
        case .headingList: String(localized: .notesGuideHeadingList)
        case .pageList: String(localized: .notesGuidePageList)
        case .kindList: String(localized: .notesGuideKindList)
        case .languageList: String(localized: .notesGuideLanguageList)
        case .symbolsByCategory: String(localized: .notesGuideSymbolsByCategory)
        case .environmentList: String(localized: .notesGuideEnvironmentList)
        case .nextItem: String(localized: .notesGuideNextItem)
        case .emptyItem: String(localized: .notesGuideEmptyItem)
        case .listEnded: String(localized: .notesGuideListEnded)
        case .selection: String(localized: .notesGuideSelection)
        case .secondaryClick: String(localized: .notesGuideSecondaryClick)
        }
    }
}

struct InputGuideRequest: Identifiable {
    let id = UUID()
    let syntax: MathSyntax
}
