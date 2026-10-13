/// When an edit to a sticky is written.
///
/// Pure, so the rule can be tested with durations instead of waiting.
enum StickyAutosavePolicy {
    /// How long typing must pause before it is written.
    static let defaultDelay: Duration = .milliseconds(400)
    /// The most an unsaved change may wait, however long typing goes on. A
    /// crash then loses at most this much.
    static let defaultCeiling: Duration = .seconds(2)

    /// How long to wait from an edit.
    ///
    /// - Parameter sinceFirstChange: how long ago the oldest change that has
    ///   not been written was made.
    static func delay(
        debounce: Duration,
        ceiling: Duration,
        sinceFirstChange elapsed: Duration
    ) -> Duration {
        max(.zero, min(debounce, ceiling - elapsed))
    }
}
