/// The names the app is known by outside its own code.
///
/// One place, so renaming the app is a change here and in the Xcode project,
/// and nowhere in between.
public enum StickyKitIdentity {
    /// The app's bundle identifier. Names the log subsystem and the folder
    /// stickies are kept in.
    public static let bundleIdentifier = "com.joaocosta.Scraps"
    /// The Darwin notification every write posts. It carries no payload, so a
    /// listener reads the store again.
    static let changesDarwinName = "\(bundleIdentifier).stickies-did-change"
}
