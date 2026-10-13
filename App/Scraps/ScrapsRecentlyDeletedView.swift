import StickyDomain
import StickyEditor
import StickyUI
import SwiftUI

struct ScrapsRecentlyDeletedView: View {
    @Bindable private var board = StickyBoard.shared

    var body: some View {
        VStack(spacing: 0) {
            if board.recentlyDeleted.isEmpty {
                ContentUnavailableView("No deleted stickies", systemImage: "trash", description: Text("Closed stickies appear here for 30 days."))
            } else {
                List(board.recentlyDeleted) { sticky in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sticky.isEmpty ? String(localized: "Untitled") : sticky.title).font(.headline).lineLimit(1)
                            Text(sticky.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if let date = sticky.deletedAt {
                                Text(date, style: .date).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Restore") { board.restoreSticky(sticky.id) }
                    }
                    .padding(.vertical, 6)
                }
            }
            Text("Stickies are permanently removed after 30 days.")
                .font(.caption).foregroundStyle(.secondary).padding()
        }
        .task { await board.refreshRecentlyDeleted() }
    }
}
