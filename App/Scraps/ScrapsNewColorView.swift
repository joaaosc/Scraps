import AppKit
import StickyDomain
import StickyEditor
import StickyUI
import SwiftUI

struct ScrapsNewColorView: View {
    @State private var color: StickyColor = .yellow
    let onCreated: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose a color").font(.headline)
            StickyColorPalette(selection: $color)
            HStack {
                Spacer()
                Button("Create Sticky") {
                    StickyBoard.shared.newSticky(color: color)
                    onCreated()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}
