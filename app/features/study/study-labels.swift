import FolioDomain
import SwiftUI

extension Verdict {
    var label: String {
        switch self {
        case .correct: String(localized: .verdictCorrect)
        case .partial: String(localized: .verdictPartial)
        case .wrong: String(localized: .verdictWrong)
        }
    }

    var tone: Tone {
        switch self {
        case .correct: .success
        case .partial: .warning
        case .wrong: .danger
        }
    }
}

extension WrongReason {
    var label: String {
        switch self {
        case .concept: String(localized: .wrongReasonConcept)
        case .method: String(localized: .wrongReasonMethod)
        case .calculation: String(localized: .wrongReasonCalculation)
        case .misread: String(localized: .wrongReasonMisread)
        case .time: String(localized: .wrongReasonTime)
        }
    }
}

extension ProblemSource {
    var label: String {
        switch self {
        case .pastExam: String(localized: .problemSourcePastExam)
        case .textbook: String(localized: .problemSourceTextbook)
        case .exercise: String(localized: .problemSourceExercise)
        case .assignment: String(localized: .problemSourceAssignment)
        case .claude: String(localized: .problemSourceClaude)
        }
    }
}

extension ProblemFormat {
    var label: String {
        switch self {
        case .trueFalse: String(localized: .problemFormatTrueFalse)
        case .choice: String(localized: .problemFormatChoice)
        case .short: String(localized: .problemFormatShort)
        case .written: String(localized: .problemFormatWritten)
        }
    }
}

extension SolveMode {
    var label: String {
        switch self {
        case .typing: String(localized: .solveModeTyping)
        case .handwriting: String(localized: .solveModeHandwriting)
        case .mock: String(localized: .solveModeMock)
        }
    }
}

extension GradeBasis {
    var label: String {
        switch self {
        case .key: String(localized: .gradeBasisKey)
        case .solution: String(localized: .gradeBasisSolution)
        case .claude: String(localized: .gradeBasisClaude)
        case .user: String(localized: .gradeBasisUser)
        }
    }
}

extension ReadinessState {
    var tone: Tone {
        switch self {
        case .ready: .success
        case .weak: .warning
        case .fewProblems: .danger
        case .noVerdict, .fewVerdicts: .plain
        }
    }
}

extension WrongStatus {
    // 카드와 문제 행의 칩이다. 틀린 적이 없으면 칩을 두지 않는다.
    var problemChip: (text: String, tone: Tone)? {
        switch self {
        case .open: (String(localized: .studyStatusWrong), .danger)
        case .recheck: (String(localized: .studyStatusRecheck), .warning)
        case .resolved: (String(localized: .studyStatusResolved), .success)
        case .untried, .neverWrong: nil
        }
    }

    var cardChip: (text: String, tone: Tone)? {
        switch self {
        case .open: (String(localized: .cardsUnknown), .danger)
        case .recheck: (String(localized: .studyStatusRecheck), .warning)
        case .resolved, .neverWrong: (String(localized: .cardsKnown), .success)
        case .untried: nil
        }
    }
}

extension CardKind {
    var label: String {
        switch self {
        case .flip: String(localized: .cardsKindFlip)
        case .trueFalse: String(localized: .cardsKindTrueFalse)
        }
    }
}

extension StudyCard {
    // 목록에서 앞면 아래에 적는 줄이다. 참거짓 카드는 답을 이유 앞에 적는다.
    var backLine: String {
        guard kind == .trueFalse, let answer else { return back }
        return [String(localized: answer ? .solveTrue : .solveFalse), back].joined(separator: " · ")
    }
}

extension CardSource {
    var label: String {
        switch self {
        case .manual: String(localized: .cardSourceManual)
        case .note: String(localized: .cardSourceNote)
        case .claude: String(localized: .cardSourceClaude)
        }
    }
}
