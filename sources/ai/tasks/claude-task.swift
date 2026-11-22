import FolioDomain
import Foundation

public enum ClaudeTask: String, Codable, Sendable, CaseIterable {
    case chat, reviewNoteDraft, examSummaryDraft, cardSuggestions, grading, sameAnswer, extractProblems, problemSheet, classifyFile,
        extractAssignment, extractGradingPolicy, examPlan, widget, lectureSections
}
