import AppIntents
import OSLog
import StickyDomain
import StickyEditor
import StickyIntents
import StickyStorage
import StickyUI
import SwiftUI

@main
struct ScrapsApp: App {
    @NSApplicationDelegateAdaptor(ScrapsApplicationDelegate.self) private var applicationDelegate

    init() {
        UserDefaults.standard.register(defaults: [
            "defaultStickyColor": StickyColor.clear.rawValue,
            "defaultFloatsOnTop": true,
            "defaultAppearsOnAllSpaces": false,
            "globalShortcutEnabled": false,
        ])
        do {
            StickyBoard.shared.connect(to: try FileStickyStore())
        } catch {
            Logger(subsystem: StickyKitIdentity.bundleIdentifier, category: "App")
                .error("Could not open the stickies folder: \(error.localizedDescription, privacy: .public)")
        }
        ScrapsUtilityWindows.shared.configure()
    }

    var body: some Scene {
        Settings { ScrapsSettingsView() }
            .commands { ScrapsCommands() }
    }
}
