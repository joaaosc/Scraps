import SwiftUI

/// What the last send or save said, in words, below a sticky's text.
struct StickyStatusLine: View {
    let status: StickyModel.Status

    var body: some View {
        Label(message, systemImage: symbolName)
            .font(.caption)
            .foregroundStyle(isFailure ? Color.red : Color.secondary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .help(message)
            .onChange(of: status, initial: true) { _, _ in
                AccessibilityNotification.Announcement(message).post()
            }
    }

    private var message: String {
        switch status {
        case .sentToNotes: String(localized: "Sent to Notes", bundle: .module)
        case .shared: String(localized: "Shared", bundle: .module)
        case let .failure(reason): reason
        }
    }

    private var isFailure: Bool {
        if case .failure = status { return true }
        return false
    }

    private var symbolName: String {
        switch status {
        case .sentToNotes, .shared: "checkmark.circle"
        case .failure: "exclamationmark.triangle"
        }
    }
}
