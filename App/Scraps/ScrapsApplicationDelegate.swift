import AppKit
import OSLog
import StickyIntents
import StickyStorage
import StickySync
import StickyUI

final class ScrapsApplicationDelegate: NSObject, NSApplicationDelegate {
    /// Brings back the stickies left open last time. Windows are made here and
    /// not earlier, once launching is over, which is when AppKit expects them.
    func applicationDidFinishLaunching(_ notification: Notification) {
        StickyBoard.shared.start()
        StickyCloudSync.shared.start()
        NSApplication.shared.registerForRemoteNotifications()
        ScrapsWelcome.leaveOnFirstLaunch()
        Task {
            do { try await StickyActionIndex.rebuild() }
            catch {
                Logger(subsystem: StickyKitIdentity.bundleIdentifier, category: "Spotlight")
                    .error("Could not update the action index: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        if let id = StickyNavigation.noteID(from: userActivity) {
            Task { await openNote(id) }
            return true
        }
        guard let action = StickyActionEntity.action(from: userActivity) else { return false }
        Task {
            do { try await StickyActionRouter.perform(action) }
            catch {
                let alert = NSAlert()
                alert.messageText = String(localized: "Could not open this action")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let route = StickyNavigation(url: url) else { continue }
            switch route {
            case let .note(id): Task { await openNote(id) }
            case .new: StickyBoard.shared.newSticky()
            case .library: ScrapsUtilityWindows.shared.showLibrary()
            }
        }
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { await StickyCloudSync.shared.synchronize() }
    }

    private func openNote(_ id: UUID) async {
        if await StickyBoard.shared.openStoredSticky(id) { return }
        await StickyCloudSync.shared.synchronize()
        if await StickyBoard.shared.openStoredSticky(id) { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "This note has not reached this device yet")
        alert.informativeText = String(localized: "Enable iCloud sync on both devices and try again.")
        alert.runModal()
    }

    /// Gives pending writes two seconds to finish and keeps the app open when
    /// saving fails or needs longer, so the editor's draft remains available.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard StickyBoard.shared.hasOpenStickies || StickyBoard.shared.hasPendingStoreOperations else { return .terminateNow }
        Task { @MainActor in
            let saved = await StickyBoard.shared.flushAll(within: .seconds(2))
            sender.reply(toApplicationShouldTerminate: saved)
            if !saved {
                sender.activate()
                let alert = NSAlert()
                alert.messageText = String(localized: "Scraps could not finish saving")
                alert.informativeText = String(localized: "Your notes are still open. Check the save error or wait for saving to finish, then try quitting again.")
                alert.addButton(withTitle: String(localized: "OK"))
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
        return .terminateLater
    }

    /// A reopen never makes a sticky. The Dock sends one, but so does every
    /// intent that brings the app forward, before the intent itself runs:
    /// answering it with an empty sticky left a blank one beside the sticky
    /// the intent was asked for.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        false
    }
}
