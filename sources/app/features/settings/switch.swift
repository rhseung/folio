import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

struct Switch: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
    }
}
