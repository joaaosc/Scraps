/// The names the app is known by outside its own code.
///
/// One place, so renaming the app is a change here and in the Xcode project,
/// and nowhere in between.
import Foundation

public enum StickyKitIdentity {
    /// The app's bundle identifier. Names the log subsystem and the folder
    /// stickies are kept in.
    public static let bundleIdentifier = "com.joaocosta.Scraps"
    public static let cloudContainerIdentifier = "iCloud.\(bundleIdentifier)"
    public static let handoffActivityType = "\(bundleIdentifier).edit"
    public static var appGroupIdentifier: String {
        #if os(macOS)
        "33FPG9442W.\(bundleIdentifier)"
        #else
        "group.\(bundleIdentifier)"
        #endif
    }
    /// The Darwin notification every write posts. It carries no payload, so a
    /// listener reads the store again.
    static let changesDarwinName = "\(bundleIdentifier).stickies-did-change"
}
