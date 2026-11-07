import FolioDomain

/// Every action, in one place: `folio actions --check` fails on any of them without a CLI command or an equivalence test.
public enum Actions {
    public static let all: [any Action.Type] = platform + [
        SemesterAdd.self, SemesterSet.self, SemesterSource.self, TranscriptAdd.self, TranscriptMove.self, CourseAdd.self, CourseRename.self, CourseSet.self, GraduationSet.self, RequirementAccept.self, CatalogSet.self,
        SettingsSet.self,
        SessionAdd.self, SessionRemove.self, SessionSet.self, SessionNote.self, SessionProgress.self, SessionWrapUp.self, SessionLinkViewed.self, AttendanceSet.self,
        UnitAdd.self, UnitRemove.self, UnitSet.self, UnitMove.self, UnitLink.self, UnitPagesAdd.self, UnitPagesSet.self, UnitPagesRemove.self, MaterialSplit.self,
        ExamAdd.self, ExamSet.self, ExamRemove.self, ExamScope.self, ExamScopeTaught.self, ExamPlanAdd.self, ExamPlanRemove.self, ExamPlanCheck.self, ExamSummary.self,
        AssignmentAdd.self, AssignmentSave.self, AssignmentStatusSet.self, AssignmentRemove.self,
        ScoreAdd.self, ScoreSet.self, ScoreRemove.self, ComponentAdd.self, ComponentSet.self, ComponentRemove.self, ComponentMove.self, PolicySet.self,
        MaterialLinkSession.self, MaterialLinkUnit.self, MaterialLinkExam.self, MaterialStatusSet.self, MaterialKindSet.self, MaterialRelink.self, MaterialUntrack.self,
        MaterialTrack.self, MaterialImport.self, MaterialMove.self, MaterialTrash.self, MaterialWrite.self, MaterialNew.self, MaterialBuild.self, CleanupApply.self, CleanupUndo.self,
        RecordingTrim.self, RecordingRetitleLegacy.self,
        NoteAdd.self, NoteWrite.self, NoteEdit.self, NoteAdopt.self, NoteLink.self, NoteLinkSessions.self, NoteUnlinkSession.self, NoteRemove.self, NoteMigrate.self, NoteRetitleSessions.self, NoteMove.self, NoteBuild.self,
        QuizCardSave.self, QuizCardRemove.self, QuizRecord.self,
        ProblemSetSave.self, ProblemSetRemove.self, ProblemLinkUnit.self, ProblemRecord.self,
        ReviewRecord.self, ReviewSkip.self,
        ImportNotion.self, ImportNotes.self, ImportCalendar.self, ImportExams.self, ImportUnits.self, ImportRequirements.self, ImportHandbook.self,
    ]

    /// How each command's proposal stands to an earlier one for the same item (`Chat.supersededProposals`). A
    /// `set` action whose every other field is a `Patch` writes only the fields it names. Everything else is left
    /// out: it adds, makes, removes or logs, and a later proposal of it doesn't make an earlier one pointless.
    public static let targets: [String: ProposalTarget] = {
        func arguments(_ type: any Action.Type) -> [String] { type.spec.fields.filter { $0.role == .argument }.map(\.name) }
        var targets = Dictionary(all.compactMap { type -> (String, ProposalTarget)? in
            let values = type.spec.fields.filter { $0.role != .argument }
            guard type.spec.effect == .changes, !values.isEmpty, values.allSatisfy(\.patch) else { return nil }
            return (type.command, ProposalTarget(arguments: arguments(type), effect: .sets))
        }, uniquingKeysWith: { a, _ in a })
        // The specs can't tell these from `note edit`, which appends: their fields are plain values, not `Patch`.
        // A rewrite leaves nothing of an earlier rewrite or edit of the same file. `note link` writes its kind and
        // links; a link left out is cleared rather than kept, so treating it as kept only ever supersedes less.
        targets[NoteWrite.command] = ProposalTarget(arguments: arguments(NoteWrite.self), effect: .replaces(covers: [NoteEdit.command]))
        targets[MaterialWrite.command] = ProposalTarget(arguments: arguments(MaterialWrite.self), effect: .replaces(covers: []))
        targets[NoteLink.command] = ProposalTarget(arguments: arguments(NoteLink.self), effect: .sets)
        return targets
    }()

    /// Backups shell out to ditto and live on the Mac only.
    #if os(macOS)
    static let platform: [any Action.Type] = [BackupCreate.self, BackupRestore.self]
    #else
    static let platform: [any Action.Type] = []
    #endif
}
