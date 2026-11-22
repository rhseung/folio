import FolioDomain
import SwiftUI

extension EnvironmentValues {
    @Entry var sheetRoom: CGFloat?
    // 시트가 창보다 넓어지지 않게 창 안쪽의 폭을 내려 준다. 넓은 시트(뽑은 문제 검토)는 이 폭까지만 넓어진다.
    @Entry var sheetWidthRoom: CGFloat?
    @Entry var textAreaRoom: CGFloat?
}
