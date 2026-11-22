import FolioDomain
import Foundation

public enum ClaudeTask: String, Codable, Sendable, CaseIterable {
    case chat, reviewNoteDraft, examSummaryDraft, cardSuggestions, grading, collectionGrading, sameAnswer, extractProblems, problemSheet,
        problemArt,
        classifyFile,
        extractAssignment, extractGradingPolicy, examPlan, widget, lectureSections
}
