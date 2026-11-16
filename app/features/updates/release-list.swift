import FolioDomain
import Foundation
import Observation

struct ReleaseList: ReleaseFeed {
    var list: [PatchNotes.Release]
    var fails = false

    func releases() async throws -> [PatchNotes.Release] {
        if fails { throw URLError(.notConnectedToInternet) }
        return list
    }
}

#if DEBUG
extension ReleaseList {
    static let sample: [PatchNotes.Release] = [
        PatchNotes.Release(
            version: PatchNotes.Version(0, 3, 0), date: Date(timeIntervalSince1970: 1_794_193_200),
            items: PatchNotes.items(
                in: """
                    ## 패치 노트
                    - feat: 노트 옆 칸의 제목 목차와 [TOC] 블록
                    - feat: 수업 시각에 녹음, 러프 노트, 렉처 자동 열기 (folio://settings/recording)
                    - feat: 수식 안에서 \\만 쳐도 뜨는 기호와 스니펫 목록
                    - feat: 미리보기 그림 크게 보기
                    - change: 빠른 추가의 과목, 마감, 반복 칩이 처음부터 흐리게 보임 (folio://today)
                    - change: 편집 보기의 수식 말풍선을 미리보기와 같은 KaTeX로 그림
                    - fix: 수식 말풍선 위와 오른쪽의 빈 여백
                    - fix: 여러 줄 칸이 글을 따라 12줄까지 늘어남
                    """)),
        PatchNotes.Release(
            version: PatchNotes.Version(0, 2, 1), date: Date(timeIntervalSince1970: 1_794_106_800),
            items: PatchNotes.items(
                in: """
                    ## 패치 노트
                    - change: 칸 경계를 끌면 부드럽게 따라옴
                    - fix: 칸이 둘 이상인 탭에서 칸을 닫으면 앱이 꺼지던 문제
                    - fix: 표 칸 안의 [[링크|이름]]이 잘리던 문제
                    """)),
        PatchNotes.Release(
            version: PatchNotes.Version(0, 2, 0), date: Date(timeIntervalSince1970: 1_794_020_400),
            items: PatchNotes.items(
                in: """
                    ## 패치 노트
                    - feat: 툴바 줄의 창 탭
                    - feat: 한 탭 안에서 두 화면을 나란히 보는 칸 나누기
                    - feat: 오늘 화면의 수업 정리 시트 (folio://today)
                    - change: 스크롤 막대 대신 넘길 것이 남은 쪽 가장자리를 흐림
                    - fix: 단원 나누기 화면에서 취소하면 앱이 꺼지던 문제
                    """)),
    ]
}
#endif
