import Foundation
import StickyUI

/// The one sticky the app makes on its own: the first time it is ever opened,
/// so a first launch shows something and says how to make the next.
///
/// Later launches with no stickies show none, as Stickies does. Opening an
/// empty one every time would leave a second, blank sticky beside the one an
/// intent that launched the app was asked to make.
enum ScrapsWelcome {
    private static let shownKey = "hasShownWelcome"

    static let text = """
        Welcome to Scraps

        Press ⌘N for a new sticky, or type Scraps in Spotlight and press Tab.

        Drag the bar at the bottom to move a sticky. Close it when you are done with it.
        """

    static func leaveOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: shownKey) else { return }
        Task {
            // Marked only once it is stored, so a failure tries again next time.
            guard (try? await StickyBoard.shared.addSticky(text: text)) != nil else { return }
            UserDefaults.standard.set(true, forKey: shownKey)
        }
    }
}
