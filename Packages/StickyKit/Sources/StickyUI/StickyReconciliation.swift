import Foundation

/// What to do so the windows on screen match the stickies in the store.
///
/// Pure on purpose: the rule is the part that can go wrong in a way nobody
/// sees — a window that never opens, or one that outlives its sticky — and it
/// can be read and tested without a window server.
struct StickyReconciliation: Equatable {
    /// Readable and not on screen, in storage order.
    let toOpen: [UUID]
    /// On screen but really gone, in the order they were opened.
    let toClose: [UUID]

    /// - Parameters:
    ///   - stored: the stickies that could be read.
    ///   - present: every sticky that exists, readable or not. A window whose
    ///     sticky is present but unreadable stays open: the file may be mid-write
    ///     or damaged, and closing would throw away text the window still holds.
    ///   - open: the stickies that have a window.
    init(stored: [UUID], present: Set<UUID>? = nil, open: [UUID]) {
        let openSet = Set(open)
        let present = present ?? Set(stored)
        // A sticky read a moment before it was deleted is listed as stored but
        // no longer present; it is gone, so no window opens for it.
        toOpen = stored.filter { !openSet.contains($0) && present.contains($0) }
        toClose = open.filter { !present.contains($0) }
    }

    var isEmpty: Bool { toOpen.isEmpty && toClose.isEmpty }
}
