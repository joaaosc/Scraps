import Foundation
import StickyDomain
#if os(macOS)
import StickyUI
#endif

public enum StickyActionRoutingError: Error, LocalizedError, Sendable {
    case appUnavailable

    public var errorDescription: String? {
        String(localized: "This action could not be opened. Open the app and try again.", bundle: .module)
    }
}

/// The universal app supplies its scene routing on iOS. On macOS the board
/// remains the single entry point for creating and reconciling sticky windows.
@MainActor
public enum StickyActionRouter {
    public static var handler: (@MainActor @Sendable (StickyAction, String?, StickyColor?) async throws -> Void)?
    public static var showAllHandler: (@MainActor @Sendable () async throws -> Void)?

    public static func perform(
        _ action: StickyAction,
        text: String? = nil,
        color: StickyColor? = nil
    ) async throws {
        if let handler {
            try await handler(action, text, color)
            return
        }
        #if os(macOS)
        switch action {
        case .newSticky:
            try await StickyBoard.shared.addSticky(text: text ?? "", color: color)
        case .newSessionSticky:
            try await StickyBoard.shared.addSticky(text: text ?? "", color: color, sessionOnly: true)
        case .newStickyInColor:
            StickyBoard.shared.newStickyInColor()
        case .settings:
            StickyBoard.shared.showSettings()
        }
        #else
        throw StickyActionRoutingError.appUnavailable
        #endif
    }

    /// Kept separate from the four indexed actions: this existing Siri and
    /// Shortcuts operation does not add a fifth app-scoped Spotlight item.
    public static func showAll() async throws {
        if let showAllHandler {
            try await showAllHandler()
            return
        }
        #if os(macOS)
        StickyBoard.shared.showAll()
        #else
        throw StickyActionRoutingError.appUnavailable
        #endif
    }
}
