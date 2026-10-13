import AppKit
import StickyUI

final class ScrapsApplicationDelegate: NSObject, NSApplicationDelegate {
    /// Brings back the stickies left open last time. Windows are made here and
    /// not earlier, once launching is over, which is when AppKit expects them.
    func applicationDidFinishLaunching(_ notification: Notification) {
        StickyBoard.shared.start()
        ScrapsWelcome.leaveOnFirstLaunch()
    }

    /// Lets the open stickies write what they have not saved yet before the app
    /// ends, waiting no longer than two seconds for it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard StickyBoard.shared.hasOpenStickies else { return .terminateNow }
        Task { @MainActor in
            await StickyBoard.shared.flushAll(within: .seconds(2))
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
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
