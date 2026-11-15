# MCP와 Claude 패널

`folio mcp`와 앱의 Claude 패널을 고칠 때 읽는다. 사용법은 `folio help mcp`와 스킬(`.claude/skills/folio/SKILL.md`)에 있다.

## 도구

- `folio mcp`는 모든 쓰기 액션과 읽기 명령을 표준 입출력 MCP 도구로 연다. 도구 결과의 JSON은 한 줄로 줄이고 null, 빈 배열, 빈 객체를 뺀다.
- 도구 정의는 질문마다 함께 가므로 `--propose`에는 과목 대화에 쓰는 도구만 연다(액션과 읽기 선언은 `panel: true`, 손 읽기 명령은 `HandRead.panel`). 나머지에는 범용 도구 두 개로 닿는다. `action_search`는 `folio help <하고 싶은 일>`의 검색으로 명령과 입력 형식(JSON Schema)을 찾고, `action_run`은 명령 이름과 JSON 입력으로 그 명령의 도구를 그대로 부른다. 그래서 `--propose`의 쓰기는 제안이 되고, 성적 잠금은 명령 자신이 지킨다. 터미널의 `folio mcp`에도 같은 두 도구가 있다.
- 손 명령 `add`(빠른 추가 한 줄)는 MCP에서 쓰기 도구로 연다(`MCPServer.builds`).

## 제안 단계

- 앱의 Claude 패널은 `folio mcp --propose`로 붙여 쓰기를 제안으로만 받는다(`docs/axes.md` "제안").
- `--propose` 서버는 한 답(질문마다 새 프로세스)의 제안을 GIST 폴더의 임시 사본(`StagedFolder`, APFS 복제)에 차례로 실제로 실행해 쌓는다(`ProposalStage`). 다음 쓰기의 미리 실행과 읽기가 그 사본에서 돌아서, `unit add` 뒤의 `unit pages add`, `note add` 뒤의 `note edit`이 제안 단계에서 통과하고, 읽은 결과의 그 항목에는 `proposed`가 붙는다. 사본에 없는 이 기기의 색인을 읽는 `search`는 `HandRead.staged`로 뺀다.
- 사본 안에서는 `CoordinatedFile`이 사본 밖으로 가는 쓰기를 막는다.
- 폴더만으로는 실패하는 제안은 기대는 앞 제안의 번호(`ActionProposal.after`)를 지닌다. 패널은 그 제안이 적용되기 전에는 따로 적용하지 않고(`ChatMessage.waiting`), 모두 적용은 같은 사본 검사(`Workspace.stagedRefusal`)로 차례대로 확인한다.
- 패널의 제안 카드는 그림을 노트에서처럼 지금 모양(라이트나 다크)으로 보인다.
- 대화의 제안은 패널과 LMS 탭(`folio://lms`)에서 같은 대화 파일을 고쳐 적용하거나 무시한다. 어느 쪽에서 바꿔도 `Workspace.chatsRevision`이 올라 다른 쪽이 다시 읽는다. 무시한 제안에 기대는 제안은 따로 적용하지 않는다.

## 자료 읽기(#85)

- `material read`(PDF의 쪽 글과 쪽 그림), `recording transcript`(받아쓰기), `note images`(노트의 그림)는 패널과 터미널의 `folio mcp`가 함께 쓰고, 그림은 MCP image content로 준다. 터미널에서는 `--out <폴더>`(GIST 폴더 밖)에 쓴다. 읽기라 액션이 아니고 아무것도 쓰지 않는다.
- 한 번에 주는 양은 `ReadingLimit`이 정하고, 넘으면 잘라서 다음 범위를 알려 준다.
- 쪽 글의 규칙(그림 자리 문자 U+FFFC 빼기, 첫 네 줄 중 가장 큰 글자를 제목으로)은 `PageText` 하나이고, PDFKit 읽기와 그림 줄이기는 `FolioStorage`의 `PDFPages`다.
