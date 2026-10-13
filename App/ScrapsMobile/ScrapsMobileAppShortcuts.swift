import AppIntents
import StickyIntents

/// The provider belongs to the application target so the metadata processor
/// publishes its phrases alongside the imported intents package.
struct ScrapsMobileAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewStickyIntent(),
            phrases: [
                "New \(.applicationName) sticky",
                "New sticky in \(.applicationName)",
            ],
            shortTitle: "New Sticky",
            systemImageName: "note.text.badge.plus"
        )
        AppShortcut(
            intent: ShowStickiesIntent(),
            phrases: [
                "Show \(.applicationName) stickies",
                "Show all stickies in \(.applicationName)",
            ],
            shortTitle: "Show All Stickies",
            systemImageName: "square.on.square"
        )
    }
}
