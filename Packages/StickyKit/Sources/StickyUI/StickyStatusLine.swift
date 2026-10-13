import SwiftUI

/// What the last send or save said, in words, below a sticky's text.
struct StickyStatusLine: View {
    let status: StickyModel.Status

    var body: some View {
        Label(message, systemImage: symbolName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
            .onAppear {
                AccessibilityNotification.Announcement(message).post()
            }
    }

    private var message: String {
        switch status {
        case .sentToNotes: "Sent to Notes"
        case .shared: "Shared"
        case let .failure(reason): reason
        }
    }

    private var symbolName: String {
        switch status {
        case .sentToNotes, .shared: "checkmark.circle"
        case .failure: "exclamationmark.triangle"
        }
    }
}
