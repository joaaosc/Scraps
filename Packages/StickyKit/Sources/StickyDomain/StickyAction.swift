import Foundation

/// The entire app-scoped Spotlight catalog. Notes never become actions or
/// searchable entities; these four stable identifiers survive app upgrades.
public enum StickyAction: String, CaseIterable, Codable, Sendable {
    case newSticky = "new-sticky"
    case newSessionSticky = "new-session-sticky"
    case newStickyInColor = "new-sticky-in-color"
    case settings = "settings"

    public var title: String {
        switch self {
        case .newSticky: "New Sticky"
        case .newSessionSticky: "New Sticky (This Session Only)"
        case .newStickyInColor: "New Sticky in Color…"
        case .settings: "Settings"
        }
    }

    /// Both entity donation priority and Spotlight's 0–100 ranking hint use
    /// this value. The order of `allCases` is the intended menu order.
    public var priority: Int {
        switch self {
        case .newSticky: 100
        case .newSessionSticky: 75
        case .newStickyInColor: 50
        case .settings: 25
        }
    }

    public var symbol: String {
        switch self {
        case .newSticky: "note.text.badge.plus"
        case .newSessionSticky: "clock"
        case .newStickyInColor: "paintpalette"
        case .settings: "gearshape"
        }
    }

    /// Resolves known IDs only, without duplicating results or allowing the
    /// caller's identifier order to change the fixed action order.
    public static func identified(by identifiers: [String]) -> [StickyAction] {
        let requested = Set(identifiers)
        return allCases.filter { requested.contains($0.rawValue) }
    }

    /// A small name query shared by App Intents and portable rule tests.
    /// Every token must match the action's title. An empty query suggests all
    /// four actions, in their fixed order, without reading any sticky store.
    public static func matching(
        _ query: String,
        localizedTitles: [StickyAction: String] = [:]
    ) -> [StickyAction] {
        let locale = Locale(identifier: "en_US_POSIX")
        let tokens = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: locale
        ).split(whereSeparator: \.isWhitespace)

        return allCases.filter { action in
            let names = [action.title, localizedTitles[action]].compactMap { $0 }
            return names.contains { name in
                let title = name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: locale
                )
                return tokens.allSatisfy { title.contains($0) }
            }
        }
    }
}
