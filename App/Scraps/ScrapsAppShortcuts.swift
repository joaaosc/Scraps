import AppIntents
import StickyIntents

/// What Spotlight lists after the app's name and Tab, and what Siri and
/// Shortcuts offer without any setup.
///
/// Declared in the app target on purpose: intents travel through
/// `StickyIntentsPackage`, but the metadata processor only extracts App
/// Shortcuts from the app itself. Declared in the package, the build compiles
/// them and publishes none.
struct ScrapsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewStickyIntent(),
            phrases: [
                "New \(.applicationName) sticky",
                "New sticky in \(.applicationName)",
            ],
            shortTitle: "New Sticky",
            systemImageName: "plus.square.on.square"
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
