import SwiftUI

struct NumberPadView: View {
    @EnvironmentObject var remote: RemoteController

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(.tertiary).frame(width: 40, height: 5).padding(.top, 8)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(1...9, id: \.self) { n in digit(n) }
                RemoteButton(key: .teletext, symbol: "text.alignleft", title: "Teletekst", size: 68)
                digit(0)
                RemoteButton(key: .backspace, symbol: "delete.left", title: "Wissen", size: 68)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func digit(_ n: Int) -> some View {
        RemoteButton(key: .digit(n), title: "\(n)", size: 68)
    }
}
