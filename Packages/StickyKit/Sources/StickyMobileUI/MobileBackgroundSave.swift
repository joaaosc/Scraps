#if os(iOS)
import UIKit

/// Ask for a brief execution window before suspension so the last edits can
/// finish their atomic file writes when the person leaves the app.
@MainActor
enum MobileBackgroundSave {
    private static var identifier: UIBackgroundTaskIdentifier = .invalid
    private static var saveTask: Task<Void, Never>?

    static func flush(_ library: MobileStickyLibrary) {
        guard saveTask == nil else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Save Stickies") {
            finishBackgroundTask()
        }
        saveTask = Task { @MainActor in
            await library.flush()
            finishBackgroundTask()
            saveTask = nil
        }
    }

    private static func finishBackgroundTask() {
        guard identifier != .invalid else { return }
        let completed = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(completed)
    }
}
#endif
