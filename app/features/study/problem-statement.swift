import FolioDomain
import SwiftUI

// 문제 하나를 보인다. 소문제는 지문과 그 그림을 먼저 보이고, 그 아래에 자기 글과 그림을 보인다. 그림은 문제지 PDF(`sheet`)의
// 칸을 잘라 그린다. 문제지 파일이 없으면(Claude가 쓴 문제지) 그림 칸도 없다.
struct ProblemStatement: View {
    let problem: Problem
    var group: ProblemGroup?
    var sheet: URL?
    var lineLimit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let group {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    StudyText(text: group.text).lineLimit(lineLimit).foregroundStyle(Theme.Palette.textSecondary)
                    ForEach(group.figures, id: \.self) { PDFRegionImage(url: sheet, region: $0) }
                }
            }
            StudyText(text: problem.text).lineLimit(lineLimit)
            ForEach(problem.figures, id: \.self) { PDFRegionImage(url: sheet, region: $0) }
        }
    }
}
