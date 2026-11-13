import FolioDomain

public enum Actions {
    public static let all: [any Action.Type] =
        platform + [
            SemesterAdd.self, SemesterSet.self, SemesterSource.self, TranscriptAdd.self, TranscriptMove.self, CourseAdd.self,
            CourseRename.self, CourseSet.self, GraduationSet.self, RequirementAccept.self, CatalogSet.self,
            SettingsSet.self,
            SessionAdd.self, SessionRemove.self, SessionSet.self, SessionNote.self, SessionProgress.self, SessionWrapUp.self,
            SessionLinkViewed.self, AttendanceSet.self,
            UnitAdd.self, UnitRemove.self, UnitSet.self, UnitMove.self, UnitLink.self, UnitPagesAdd.self, UnitPagesSet.self,
            UnitPagesRemove.self, MaterialSplit.self,
            ExamAdd.self, ExamSet.self, ExamRemove.self, ExamScope.self, ExamScopeTaught.self, ExamPlanAdd.self, ExamPlanRemove.self,
            ExamPlanCheck.self, ExamSummary.self,
            AssignmentAdd.self, AssignmentSave.self, AssignmentStatusSet.self, AssignmentRemove.self,
            ScoreAdd.self, ScoreSet.self, ScoreRemove.self, ComponentAdd.self, ComponentSet.self, ComponentRemove.self, ComponentMove.self,
            PolicySet.self,
            MaterialLinkSession.self, MaterialLinkUnit.self, MaterialLinkExam.self, MaterialStatusSet.self, MaterialKindSet.self,
            MaterialRelink.self, MaterialUntrack.self,
            MaterialTrack.self, MaterialImport.self, MaterialMove.self, MaterialTrash.self, MaterialWrite.self, MaterialNew.self,
            MaterialBuild.self, CleanupApply.self, CleanupUndo.self,
            RecordingTrim.self, RecordingRetitleLegacy.self,
            NoteAdd.self, NoteWrite.self, NoteEdit.self, NoteAdopt.self, NoteLink.self, NoteLinkSessions.self, NoteUnlinkSession.self,
            NoteRemove.self, NoteMigrate.self, NoteRetitleSessions.self, NoteMove.self, NoteBuild.self,
            NoteFigureAdd.self, NoteFigureWrite.self, NoteWidgetAdd.self, NoteWidgetWrite.self,
            QuizCardSave.self, QuizCardRemove.self, QuizRecord.self,
            ProblemSetSave.self, ProblemSetRemove.self, ProblemLinkUnit.self, ProblemRecord.self,
            ReviewRecord.self, ReviewSkip.self,
            LMSSeen.self, LMSMark.self, LMSAccept.self,
            ImportNotion.self, ImportNotes.self, ImportCalendar.self, ImportExams.self, ImportUnits.self, ImportRequirements.self,
            ImportHandbook.self,
        ]

    public static let targets: [String: ProposalTarget] = {
        func arguments(_ type: any Action.Type) -> [String] { type.spec.fields.filter { $0.role == .argument }.map(\.name) }
        var targets = Dictionary(
            all.compactMap { type -> (String, ProposalTarget)? in
                let values = type.spec.fields.filter { $0.role != .argument }
                guard type.spec.effect == .changes, !values.isEmpty, values.allSatisfy(\.patch) else { return nil }
                return (type.command, ProposalTarget(arguments: arguments(type), effect: .sets))
            }, uniquingKeysWith: { a, _ in a })

        // spec으로는 이 액션들을 덧붙이는 `note edit`와 구분할 수 없다. 필드가 `Patch`가 아니라 맨 값이기 때문이다. 다시
        // 쓰기는 같은 파일의 앞선 다시 쓰기나 편집을 아무것도 남기지 않는다. `note link`는 종류와 링크를 쓰고 빠진 링크를
        // 지우므로, 이것을 지키는 것으로 다뤄도 덜 대체할 뿐이다.
        targets[NoteWrite.command] = ProposalTarget(arguments: arguments(NoteWrite.self), effect: .replaces(covers: [NoteEdit.command]))
        targets[MaterialWrite.command] = ProposalTarget(arguments: arguments(MaterialWrite.self), effect: .replaces(covers: []))
        targets[NoteFigureWrite.command] = ProposalTarget(arguments: arguments(NoteFigureWrite.self), effect: .replaces(covers: []))
        targets[NoteWidgetWrite.command] = ProposalTarget(arguments: arguments(NoteWidgetWrite.self), effect: .replaces(covers: []))
        targets[NoteLink.command] = ProposalTarget(arguments: arguments(NoteLink.self), effect: .sets)
        return targets
    }()

    #if os(macOS)
    static let platform: [any Action.Type] = [BackupCreate.self, BackupRestore.self]
    #else
    static let platform: [any Action.Type] = []
    #endif
}
