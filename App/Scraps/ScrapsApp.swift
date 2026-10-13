import AppIntents
import OSLog
import StickyIntents
import StickyStorage
import StickyUI
import SwiftUI

/// Publishes the intents declared in the package under this app.
struct ScrapsIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [StickyIntentsPackage.self]
    }
}

@main
struct ScrapsApp: App {
    @NSApplicationDelegateAdaptor(ScrapsApplicationDelegate.self)
    private var applicationDelegate

    private static let logger = Logger(
        subsystem: StickyKitIdentity.bundleIdentifier,
        category: "App"
    )

    init() {
        // Here rather than when launching finishes: an intent that launched
        // the app must find a board that can already create. Windows wait for
        // the delegate to say launching is over.
        do {
            StickyBoard.shared.connect(to: try FileStickyStore())
        } catch {
            // The board stays without a store, and the first attempt to make a
            // sticky says so in words.
            Self.logger.error(
                "Could not open the stickies folder: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    var body: some Scene {
        // The app is its stickies and has no window of its own. SwiftUI needs
        // one scene to hang the menu bar on, and Settings is the one that
        // opens nothing at launch; its menu item is removed until there is
        // something to set.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
            CommandGroup(replacing: .newItem) {
                Button("New Sticky") {
                    StickyBoard.shared.newSticky()
                }
                .keyboardShortcut("n")
            }
            CommandGroup(before: .windowArrangement) {
                Button("Show All Stickies") {
                    StickyBoard.shared.showAll()
                }
            }
        }
    }
}
