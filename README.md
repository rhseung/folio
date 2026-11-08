<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.png">
    <img src="docs/images/logo-light.png" alt="Folio" width="128">
  </picture>
</p>

<h1 align="center">Folio</h1>

<p align="center">Mac, iPad, iPhone, Apple Watch에서 과목을 중심으로 학업을 관리하는 앱</p>

## 기능

- **과목**: 강의 회차, 자료, 노트, 과제, 시험을 과목 하나에 모읍니다.
- **노트**: 마크다운 노트에 수식, 콜아웃, 노트 사이 링크를 씁니다.
- **복습과 퀴즈**: 단원 단위로 간격을 두고 복습하고, 서술형 답은 Claude가 채점합니다.
- **성적**: 평가 기준으로 환산 점수, 평점, 졸업 요건을 계산합니다.
- **녹음**: 강의를 녹음하고 기기 안에서 글로 받아씁니다.
- **파일**: 모든 데이터는 iCloud Drive의 파일로 남고, 명령줄 도구 `folio`로도 다룹니다.

남은 일과 진행 상황은 [GitHub Project](https://github.com/users/rhseung/projects/10)에 있습니다.

## 개발

지금은 Mac과 iPad(macOS 26, iPadOS 26 이상)를 먼저 만들고 있고, iPhone과 Apple Watch는 [플랫폼 확장(#28)](https://github.com/rhseung/folio/issues/28)에서 만듭니다. 개발에는 Xcode 27과 [mise](https://mise.jdx.dev)가 필요합니다.

```bash
mise run generate
open Folio.xcodeproj
```

빌드, 테스트, 구조와 규칙은 [AGENTS.md](AGENTS.md)에 있습니다.
