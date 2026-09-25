import SwiftUI

/// A small ⓘ button that shows a short explanation in a popover.
struct InfoButton<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                content
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
        }
    }
}
