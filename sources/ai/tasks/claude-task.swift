import FolioDomain
import Foundation

public enum ClaudeTask: String, Codable, Sendable, CaseIterable {
    case chat, reviewNoteDraft, examSummaryDraft, quizCards, grading, classifyFile, extractAssignment, extractGradingPolicy, examPlan,
        widget, lectureSections
}
