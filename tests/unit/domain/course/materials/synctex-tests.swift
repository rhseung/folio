import FolioDomain
import Foundation
import Testing

// Tectonic 0.17이 이 `ok.tex`에 대해 쓴 SyncTeX 데이터이며, 폴더 이름만 바꿨다.
//
//    1 \documentclass{article}
//    2 \begin{document}
//    3 Hello world.
//    4
//    5 Second paragraph with $x^2$.
//    6
//    7 \input{part}      % part.tex: "Included text from part.", "", "More included."
//    8
//    9 \newpage
//   10 Page two line.
//   11 \end{document}
struct SyncTeXTests {
    static let text = """
        SyncTeX Version:1
        Input:1:/course/Study/ok.tex
        Input:2:
        Input:3:
        Input:4:
        Input:5:
        Input:6:
        Input:7:/course/Study/part.tex
        Output:pdf
        Magnification:1000
        Unit:1
        X Offset:0
        Y Offset:0
        Content:
        !395
        {1
        [1,9:4736287,46220575:26673152,41484288,0
        (1,9:4736287,4736287:0,0,0
        )
        [1,9:8799519,46220575:22609920,40435712,0
        [1,9:8799519,6571295:22609920,786432,0
        (1,9:8799519,6571295:22609920,0,0
        h1,9:8799519,6571295:22609920,0,0
        )
        ]
        [1,9:8799519,44254495:22609920,36044800,0
        (1,4:8799519,8865055:22609920,454820,7208
        h1,3:8799519,8865055:983040,0,0
        g1,3:11475354,8865055
        k1,4:31409439,8865055:18165924
        g1,4:31409439,8865055
        )
        (1,6:8799519,9651487:22609920,533465,135003
        h1,5:8799519,9651487:983040,0,0
        g1,5:12003574,9651487
        g1,5:15139472,9651487
        g1,5:16632382,9651487
        $1,5:16632382,9651487
        x1,5:17006938,9651487
        (1,5:17006938,9413662:294003,295640,0
        x1,5:17268173,9413662
        )
        $1,5:17300941,9651487
        k1,6:31409439,9651487:13926308
        g1,6:31409439,9651487
        )
        (7,2:8799519,10437919:22609920,462029,127139
        h7,1:8799519,10437919:983040,0,0
        g7,1:12459049,10437919
        g7,1:13824164,10437919
        g7,1:15373435,10437919
        k7,2:31409439,10437919:14649918
        g7,2:31409439,10437919
        )
        (1,8:8799519,11224351:22609920,454820,7208
        h7,3:8799519,11224351:983040,0,0
        g7,3:11477320,11224351
        g7,3:14354351,11224351
        k1,8:31409439,11224351:17055088
        g1,8:31409439,11224351
        )
        ]
        (1,9:8799519,46220575:22609920,436470,0
        (1,9:8799519,46220575:22609920,436470,0
        k1,9:19940639,46220575:11141120
        k1,9:31409439,46220575:11141120
        )
        )
        ]
        ]
        !1287
        }1
        !9
        {2
        [1,11:4736287,46220575:26673152,41484288,0
        [1,11:8799519,46220575:22609920,40435712,0
        [1,11:8799519,6571295:22609920,786432,0
        (1,11:8799519,6571295:22609920,0,0
        h1,11:8799519,6571295:22609920,0,0
        )
        ]
        [1,11:8799519,44254495:22609920,36044800,0
        (1,11:8799519,8865055:22609920,454820,135003
        h1,10:8799519,8865055:983040,0,0
        g1,10:11375084,8865055
        g1,10:12612404,8865055
        k1,11:31409439,8865055:17595105
        g1,11:31409439,8865055
        )
        ]
        (1,11:8799519,46220575:22609920,436470,0
        (1,11:8799519,46220575:22609920,436470,0
        k1,11:19940639,46220575:11141120
        k1,11:31409439,46220575:11141120
        )
        )
        ]
        ]
        !588
        }2
        Input:8:
        !17
        Postamble:
        Count:77
        !24
        Post scriptum:
        """

    let sync = SyncTeX(text: Self.text)
    let main = "/course/Study/ok.tex"
    let part = "/course/Study/part.tex"

    // 좌표는 쪽의 왼쪽 위에서 잰 PDF point이고, article의 글은 오른쪽으로 134pt, 아래로 128pt 지점에서 시작한다.
    @Test func aWordOnTheFirstLine() {
        #expect(sync.place(page: 1, x: 200, y: 132) == SyncTeX.Place(file: main, line: 3))
    }

    // 문단의 행은 빈 줄이 문단을 끝낸 4번째 줄을 가리키고, 그 낱말은 3번째 줄에 있다.
    @Test func theWordsNameTheLineNotTheParagraphEnd() {
        #expect(sync.place(page: 1, x: 140, y: 132)?.line == 3)
        #expect(sync.place(page: 1, x: 470, y: 132)?.line == 3)
    }

    @Test func aFormulaInsideALine() {
        #expect(sync.place(page: 1, x: 260, y: 141) == SyncTeX.Place(file: main, line: 5))
    }

    @Test func anInputFileIsNamed() {
        #expect(sync.place(page: 1, x: 200, y: 158) == SyncTeX.Place(file: part, line: 1))
        #expect(sync.place(page: 1, x: 200, y: 170) == SyncTeX.Place(file: part, line: 3))
    }

    @Test func belowTheTextTheNearestLine() {
        #expect(sync.place(page: 1, x: 200, y: 300) == SyncTeX.Place(file: part, line: 3))
        #expect(sync.place(page: 1, x: 20, y: 131) == SyncTeX.Place(file: main, line: 3))
    }

    @Test func pagesAreKeptApart() {
        #expect(sync.place(page: 2, x: 200, y: 132) == SyncTeX.Place(file: main, line: 10))
        #expect(sync.place(page: 3, x: 200, y: 132) == nil)
    }

    // `-Z deterministic-mode`는 입력을 이름 없이 쓴다. 짐작한 파일보다 파일이 없는 편이 낫다.
    @Test func withoutFileNamesNothing() {
        let blanked = Self.text.replacingOccurrences(of: main, with: "").replacingOccurrences(of: part, with: "")
        #expect(SyncTeX(text: blanked).place(page: 1, x: 200, y: 132) == nil)
    }

    @Test func emptyDataHasNoPlaces() {
        #expect(SyncTeX(text: "").place(page: 1, x: 0, y: 0) == nil)
    }
}
