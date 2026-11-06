/// Every action, in one place: `folio actions --check` fails on any of them without a CLI command or an equivalence test.
public enum Actions {
    public static let all: [any Action.Type] = platform + [
        SemesterAdd.self, SemesterSet.self, SemesterSource.self, TranscriptAdd.self, TranscriptMove.self, CourseAdd.self, CourseRename.self, CourseSet.self, GraduationSet.self, RequirementAccept.self, CatalogSet.self,
        SettingsSet.self,
        SessionAdd.self, SessionRemove.self, SessionSet.self, SessionNote.self, SessionLinkViewed.self, AttendanceSet.self,
        UnitAdd.self, UnitRemove.self, UnitSet.self, UnitMove.self, UnitLink.self,
        ExamAdd.self, ExamSet.self, ExamRemove.self, ExamScope.self, ExamScopeTaught.self, ExamPlanAdd.self, ExamPlanRemove.self, ExamPlanCheck.self, ExamSummary.self,
        AssignmentAdd.self, AssignmentSave.self, AssignmentStatusSet.self, AssignmentRemove.self,
        ScoreAdd.self, ScoreSet.self, ScoreRemove.self, ComponentAdd.self, ComponentSet.self, ComponentRemove.self, ComponentMove.self, PolicySet.self,
        MaterialLinkSession.self, MaterialLinkUnit.self, MaterialLinkExam.self, MaterialStatusSet.self, MaterialKindSet.self, MaterialRelink.self, MaterialUntrack.self,
        MaterialTrack.self, MaterialImport.self, MaterialMove.self, MaterialTrash.self, MaterialWrite.self, MaterialNew.self, MaterialBuild.self, CleanupApply.self, CleanupUndo.self,
        RecordingTrim.self,
        NoteAdd.self, NoteWrite.self, NoteEdit.self, NoteAdopt.self, NoteLink.self, NoteLinkSessions.self, NoteUnlinkSession.self, NoteRemove.self, NoteMigrate.self, NoteRetitleSessions.self, NoteBuild.self,
        QuizCardSave.self, QuizCardRemove.self, QuizRecord.self,
        ProblemSetSave.self, ProblemSetRemove.self, ProblemLinkUnit.self, ProblemRecord.self,
        ReviewRecord.self, ReviewSkip.self,
        ImportNotion.self, ImportNotes.self, ImportCalendar.self, ImportExams.self, ImportUnits.self, ImportRequirements.self, ImportHandbook.self,
    ]

    /// Each command's `@Arg` fields, which pick the item a proposal is about (`Chat.supersededProposals`). A log entry
    /// adds to the ones before it, and an item made from its course alone (a session, a score) is a new one each
    /// time, so neither stands in for an earlier proposal.
    public static let targets: [String: [String]] = Dictionary(all.compactMap { type -> (String, [String])? in
        let spec = type.spec
        let arguments = spec.fields.filter { $0.role == .argument }
        guard spec.effect != .logs, spec.effect != .creates || arguments.contains(where: { $0.ref == nil }) else { return nil }
        return (spec.command, arguments.map(\.name))
    }, uniquingKeysWith: { a, _ in a })

    /// Backups shell out to ditto and live on the Mac only.
    #if os(macOS)
    static let platform: [any Action.Type] = [BackupCreate.self, BackupRestore.self]
    #else
    static let platform: [any Action.Type] = []
    #endif
}
