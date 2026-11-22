import Foundation

// 문제집과 풀이집의 머리말과 매크로다. 사용자의 `exam-problem-collection` 형식(§7.1, §7.2)을 그대로 따르고, 거기에 없는 것만 더했다.
// 더한 것은 셋이다.
// - kotex: 문제지의 언어를 바꾸지 않고 옮기므로(#575) 한국어 문제가 들어온다. Tectonic은 XeTeX라서 kotex가 xetexko를 쓴다.
// - `\stem`: 지문을 소문제 앞에 한 번 둔다. 지문이 쓴 높이(`\stemroom`)를 다음 문제 칸에서 빼고, 반 쪽 문제 아래에서는 새 쪽을
//   연다. 그러지 않으면 지문 뒤의 half 두 개가 한 쪽에 들어가지 않아 다음 쪽으로 밀리고 쪽 나눔이 모두 어긋난다.
// - `\sheetfigure`: 그림을 다시 그리지 않고 문제지 PDF의 칸을 잘라 넣는다. 칸은 쪽 크기의 비율이라 TeX이 쪽을 한 번 읽어 크기를
//   잰 뒤 trim으로 바꾼다. PDF를 그대로 넣으므로 그림은 벡터로 남는다.
enum ProblemCollectionTeX {
    static let problemsSubtitle = "Problem Collection for Exam Review"  // strings: data, 문제집 PDF의 표지
    static let solutionsSubtitle = "Solutions to the Problem Collection"  // strings: data, 풀이집 PDF의 표지
    static let noSolution = #"{\color{taggray}No answer or solution on file.}"#  // strings: data, 풀이집 PDF의 글

    // 참·거짓의 정답 값은 앱의 데이터(`Problem.trueFalseOptions`)라 한국어다. 풀이집의 글은 영어이므로 옮겨 쓴다.
    static func trueFalse(_ answer: String) -> String {
        switch answer {
        case Problem.trueFalseOptions[0]: "True"  // strings: data, 풀이집 PDF의 글
        case Problem.trueFalseOptions[1]: "False"  // strings: data, 풀이집 PDF의 글
        default: answer
        }
    }

    static func solutionPage(_ page: Int) -> String {
        #"{\color{taggray}See page \#(page) of the solution document.}"#  // strings: data, 풀이집 PDF의 글
    }

    static func problemSet(_ title: String) -> String {
        let t = ProblemCollection.escaped(title)
        return "\\problemset{\(t)}{\(t)}{}"
    }

    // 그림 칸은 Claude가 어림한 것이라 가장자리의 글자나 선을 자르기 쉬워서, 앱이 그릴 때처럼 여백을 더한다.
    static func figure(_ sheet: String, _ region: ProblemRegion) -> String {
        let r = region.padded(by: figureMargin)
        let n = [r.x, r.y, r.width, r.height].map { String(format: "%.4f", $0) }  // strings: data, TeX 숫자
        return "\\sheetfigure{\(sheet)}{\(r.page)}{\(n[0])}{\(n[1])}{\(n[2])}{\(n[3])}"
    }

    static let figureMargin = 0.01

    static func cover(title: String, subtitle: String, line: String?) -> String {
        var lines = [  // strings: data, LaTeX 표지
            #"\thispagestyle{empty}"#,
            #"\begin{center}"#,
            #"  {\LARGE\bfseries \#(title)}\par\vspace{2mm}"#,
            #"  {\Large \#(subtitle)}\par\vspace{2mm}"#,
        ]
        if let line { lines.append(#"  {\small \#(line)}\par\vspace{1mm}"#) }
        lines += [  // strings: data, LaTeX 표지
            #"  {\small\color{taggray}Last updated: \today}"#,
            #"\end{center}"#,
            #"\vspace{4mm}"#,
            #"{\color{rulegray}\hrule height 0.8pt}"#,
            #"\vspace{4mm}"#,
            #"\tableofcontents"#,
            #"\clearpage"#,
        ]
        return lines.joined(separator: "\n") + "\n\n"
    }

    static func problems(course: String, cover: String) -> String {
        header(how: problemsHow) + common(course: course, kind: "Problem Collection", packages: "") + problemsMacros
            + toc + "\n\\begin{document}\n\n" + cover
    }

    static func solutions(course: String, cover: String) -> String {
        header(how: solutionsHow) + common(course: course, kind: "Solutions", packages: ",needspace") + solutionsMacros
            + toc + "\n\\begin{document}\n\n" + cover
    }

    private static func header(how: String) -> String {
        // strings: data, LaTeX 머리 주석
        """
        % Folio가 고른 문제로 만든 파일이다. 다시 만들면 바뀌므로 손으로 고치려면 다른 이름으로 저장한다.
        % 빌드: tectonic 또는 xelatex 두 번(목차 쪽 번호). 그림은 같은 폴더의 문제지 PDF(sheet-*.pdf)에서 잘라 온다.
        \(how)

        """
    }

    private static let problemsHow = """
        % 묶음 더하기: \\problemset{HW 4}{HW 4}{} 다음에 \\prob[half|full]{HW 4}{번호}{배점 같은 표시}{문제 글}.
        % 지문: \\stem{HW 4}{지문 이름}{글}은 다음 문제 칸에서 그 높이를 뺀다.
        """  // strings: data, LaTeX 머리 주석

    private static let solutionsHow = """
        % 묶음 더하기: \\problemset{HW 4}{HW 4}{} 다음에 \\sol{HW 4}{번호}{표시}{문제 글}{\\answer{답} \\method{1}[방법] 풀이}.
        """  // strings: data, LaTeX 머리 주석

    private static func common(course: String, kind: String, packages: String) -> String {
        // strings: data, LaTeX 머리말
        #"""
        \documentclass[11pt,a4paper]{article}
        \usepackage[a4paper,top=16mm,bottom=16mm,left=18mm,right=18mm,
                    headheight=14pt,headsep=6mm,footskip=8mm]{geometry}
        \usepackage{amsmath,amssymb,amsthm,mathtools,enumitem,xcolor,fancyhdr,xparse,graphicx\#(packages)}
        \usepackage{kotex}
        \usepackage{hyperref}
        \hypersetup{colorlinks=true,linkcolor=black,urlcolor=black}
        \definecolor{rulegray}{gray}{0.55}\definecolor{taggray}{gray}{0.35}\definecolor{stmtbg}{gray}{0.95}
        \setlength{\parindent}{0pt}
        \pagestyle{fancy}\fancyhf{}
        \fancyhead[L]{\small\color{taggray}\#(course) \,--\, \#(kind)}
        \fancyhead[R]{\small\color{taggray}\leftmark}
        \fancyfoot[C]{\small\thepage}\renewcommand{\headrulewidth}{0.3pt}

        \newsavebox{\sheetpage}\newlength{\sheetw}\newlength{\sheeth}\newlength{\sheetcut}
        \NewDocumentCommand{\sheetfigure}{m m m m m m}{%
          \sbox{\sheetpage}{\includegraphics[page=#2]{#1}}%
          \setlength{\sheetw}{\wd\sheetpage}\setlength{\sheeth}{\ht\sheetpage}%
          \setlength{\sheetcut}{#5\sheetw}\ifdim\sheetcut>\linewidth\setlength{\sheetcut}{\linewidth}\fi
          \edef\sheetnext{\noexpand\includegraphics[page=#2,clip,width=\the\sheetcut,height=0.3\textheight,keepaspectratio,
            trim={\the\dimexpr#3\sheetw\relax} {\the\dimexpr\sheeth-#4\sheeth-#6\sheeth\relax}
                 {\the\dimexpr\sheetw-#3\sheetw-#5\sheetw\relax} {\the\dimexpr#4\sheeth\relax}]{#1}}%
          \par\vspace{1mm}{\centering\sheetnext\par}\vspace{1mm}}

        """#
    }

    private static let problemsMacros = #"""
        \setlist{nosep,leftmargin=*}
        \newif\iffirstonpage \newif\iftitleonpage \newlength{\probheight} \newlength{\stemroom}
        \NewDocumentCommand{\problemset}{m m m}{%
          \clearpage\markboth{#1}{#1}\addcontentsline{toc}{section}{#2}%
          {\Large\bfseries #2\par}%
          \if\relax\detokenize{#3}\relax\else\vspace{1mm}{\small\color{taggray}#3\par}\fi
          \vspace{2mm}{\color{rulegray}\hrule height 0.8pt}\vspace{4mm}%
          \global\firstonpagetrue\global\titleonpagetrue\global\stemroom=0pt}
        \NewDocumentCommand{\stem}{m m +m}{%
          \iffirstonpage\else\clearpage\global\firstonpagetrue\global\titleonpagefalse\fi
          \setbox0\vbox{\hsize\textwidth
            {\color{rulegray}\hrule height 0.4pt}\vspace{1.2mm}%
            {\bfseries #1 \,--\, #2}\par\vspace{2mm}#3\par\vspace{3mm}}%
          \global\stemroom=\dimexpr\ht0+\dp0\relax
          \par\noindent\box0\par}
        \NewDocumentCommand{\prob}{O{full} m m m +m}{%
          \def\tmpsize{#1}\def\tmphalf{half}%
          \ifx\tmpsize\tmphalf \setlength{\probheight}{0.465\textheight}%
          \else \iffirstonpage\else\clearpage\fi
            \setlength{\probheight}{\dimexpr\textheight-2\baselineskip\relax}\fi
          \iftitleonpage \ifx\tmpsize\tmphalf \addtolength{\probheight}{-1.9\baselineskip}%
            \else \addtolength{\probheight}{-3.6\baselineskip}\fi\fi
          \addtolength{\probheight}{-\stemroom}\global\stemroom=0pt
          \addcontentsline{toc}{subsection}{#2 \,--\, Problem #3}%
          \par\noindent\begin{minipage}[t][\probheight][t]{\textwidth}
            {\color{rulegray}\hrule height 0.4pt}\vspace{1.2mm}
            {\bfseries #2 \,--\, Problem #3}%
            \if\relax\detokenize{#4}\relax\else\quad{\color{taggray}#4}\fi
            \hfill{\small\color{taggray}Attempt\;$\square$\,$\square$\,$\square$}\par\vspace{2mm}
            #5\par\vspace{3mm}{\color{rulegray!50}\hrule height 0.2pt}
          \end{minipage}\par
          \ifx\tmpsize\tmphalf
            \iffirstonpage\global\firstonpagefalse\vspace{2mm}%
            \else\clearpage\global\firstonpagetrue\global\titleonpagefalse\fi
          \else\clearpage\global\firstonpagetrue\global\titleonpagefalse\fi}

        """#  // strings: data, LaTeX 매크로

    private static let solutionsMacros = #"""
        \setlength{\parskip}{1.6mm}
        \setlist{nosep,leftmargin=*,topsep=0.5mm,itemsep=0.8mm}
        \newcommand{\qedsym}{\hfill$\blacksquare$}
        \NewDocumentCommand{\problemset}{m m m}{%
          \clearpage\markboth{#1}{#1}\addcontentsline{toc}{section}{#2}%
          {\Large\bfseries #2 \,--\, Solutions\par}%
          \if\relax\detokenize{#3}\relax\else\vspace{1mm}{\small\color{taggray}#3\par}\fi
          \vspace{2mm}{\color{rulegray}\hrule height 0.8pt}\vspace{3mm}}
        \NewDocumentCommand{\solstem}{m m +m}{%
          \par\addvspace{6mm}\Needspace{8\baselineskip}%
          \noindent\colorbox{stmtbg}{\parbox{\dimexpr\textwidth-2\fboxsep\relax}{%
            \setlength{\parskip}{1mm}{\bfseries #1 \,--\, #2}\par #3}}\par}
        \NewDocumentCommand{\sol}{m m m +m +m}{%
          \par\addvspace{6mm}\Needspace{14\baselineskip}%
          \addcontentsline{toc}{subsection}{#1 \,--\, Problem #2}%
          \noindent\colorbox{stmtbg}{\parbox{\dimexpr\textwidth-2\fboxsep\relax}{%
            \setlength{\parskip}{1mm}{\bfseries #1 \,--\, Problem #2}%
            \if\relax\detokenize{#3}\relax\else\quad{\color{taggray}#3}\fi\par #4}}\par
          \vspace{1mm}#5\par}
        \NewDocumentCommand{\answer}{+m}{\par{\bfseries Answer.}\ #1\par}
        \NewDocumentCommand{\method}{m o}{%
          \par\addvspace{3mm}\Needspace{5\baselineskip}%
          {\color{rulegray!60}\hrule height 0.3pt}\vspace{1.2mm}%
          {\bfseries Solution #1}\IfValueT{#2}{\ \ {\color{taggray}(#2)}}\par}

        """#  // strings: data, LaTeX 매크로

    private static let toc = #"""
        \makeatletter
        \renewcommand{\l@section}[2]{\vspace{2mm}\noindent{\bfseries #1}\hfill{\bfseries #2}\par}
        \renewcommand{\l@subsection}[2]{\noindent\hspace*{6mm}#1\dotfill #2\par}
        \makeatother

        """#  // strings: data, LaTeX 목차 모양
}
