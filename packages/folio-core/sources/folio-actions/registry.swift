/// Every action, in one place: `folio actions --check` fails on any of them without a CLI command or an equivalence test.
public enum Actions {
    public static let all: [any Action.Type] = platform + [
        SemesterAdd.self, SemesterSet.self, TranscriptAdd.self, TranscriptSet.self, TranscriptRemove.self, CourseAdd.self, CourseRename.self, CourseSet.self, GraduationSet.self, CatalogSet.self,
        SettingsSet.self,
        SessionAdd.self, SessionRemove.self, SessionSet.self, SessionNote.self, AttendanceSet.self,
        UnitAdd.self, UnitRemove.self, UnitSet.self, UnitMove.self, UnitLink.self,
        ExamAdd.self, ExamSet.self, ExamRemove.self, ExamScope.self, ExamScopeTaught.self, ExamPlanAdd.self, ExamPlanRemove.self, ExamPlanCheck.self, ExamSummary.self,
        AssignmentAdd.self, AssignmentSave.self, AssignmentStatusSet.self, AssignmentRemove.self,
        ScoreAdd.self, ScoreSet.self, ScoreRemove.self, ComponentAdd.self, ComponentSet.self, ComponentRemove.self, ComponentMove.self, PolicySet.self,
        MaterialLinkSession.self, MaterialLinkUnit.self, MaterialStatusSet.self, MaterialRelink.self, MaterialUntrack.self,
        MaterialTrack.self, MaterialImport.self, MaterialMove.self, MaterialTrash.self, CleanupApply.self, CleanupUndo.self,
        NoteAdd.self, NoteWrite.self, NoteAdopt.self, NoteLink.self, NoteRemove.self,
        QuizCardSave.self, QuizCardRemove.self, QuizRecord.self,
        ProblemSetSave.self, ProblemSetRemove.self, ProblemLinkUnit.self, ProblemRecord.self,
        ReviewRecord.self, ReviewSkip.self,
        ImportNotion.self, ImportNotes.self, ImportCalendar.self, ImportExams.self, ImportUnits.self, ImportRequirements.self, ImportHandbook.self,
    ]

    /// Backups shell out to ditto and live on the Mac only.
    #if os(macOS)
    static let platform: [any Action.Type] = [BackupCreate.self, BackupRestore.self]
    #else
    static let platform: [any Action.Type] = []
    #endif
}
