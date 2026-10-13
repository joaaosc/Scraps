import Foundation

public struct StickyMergeResult: Sendable {
    public let note: Sticky
    public let recoveredEdit: Sticky?
}

/// A three-way merge preserves independent edits and retains a second note
/// when both devices change the text. Window geometry remains device-local.
public enum StickySyncMerge {
    public static func cloudCopy(_ note: Sticky) -> Sticky {
        var copy = note
        copy.frame = nil
        copy.isCollapsed = false
        copy.floatsOnTop = true
        copy.appearsOnAllSpaces = false
        return copy
    }

    public static func equivalent(_ first: Sticky, _ second: Sticky) -> Bool {
        var lhs = cloudCopy(first)
        var rhs = cloudCopy(second)
        lhs.updatedAt = .distantPast
        rhs.updatedAt = .distantPast
        return lhs == rhs
    }

    public static func resolve(
        local: Sticky?, remote: Sticky, ancestor: Sticky?, conflictID: UUID = UUID()
    ) -> StickyMergeResult {
        guard let local else { return StickyMergeResult(note: remote, recoveredEdit: nil) }
        var merged: Sticky
        var recovered: Sticky?
        let remoteIsNewer = revision(remote) >= revision(local)
        let preferred = remoteIsNewer ? remote : local
        if equivalent(local, remote) {
            merged = local
        } else if let ancestor, equivalent(local, ancestor) {
            merged = remote
        } else if let ancestor, equivalent(remote, ancestor) {
            merged = local
        } else {
            merged = preferred
            func choose<Value: Equatable>(_ lhs: Value, _ rhs: Value, _ base: Value?) -> Value {
                if let base, lhs == base { return rhs }
                if let base, rhs == base { return lhs }
                return remoteIsNewer ? rhs : lhs
            }
            let localTextChanged = ancestor.map { !sameText(local, $0) } ?? true
            let remoteTextChanged = ancestor.map { !sameText(remote, $0) } ?? true
            if !localTextChanged {
                merged.text = remote.text; merged.richText = remote.richText
            } else if !remoteTextChanged {
                merged.text = local.text; merged.richText = local.richText
            }
            merged.color = choose(local.color, remote.color, ancestor?.color)
            merged.isPinned = choose(local.isPinned, remote.isPinned, ancestor?.isPinned)
            merged.isArchived = choose(local.isArchived, remote.isArchived, ancestor?.isArchived)
            merged.deletedAt = choose(local.deletedAt, remote.deletedAt, ancestor.map(\.deletedAt))
            if let ancestor, local.tags == ancestor.tags { merged.tags = remote.tags }
            else if let ancestor, remote.tags == ancestor.tags { merged.tags = local.tags }
            else { merged.tags = Sticky.normalizedTags(local.tags + remote.tags) }

            let textConflict = localTextChanged && remoteTextChanged && !sameText(local, remote)
            let editAgainstDeletion = (local.deletedAt != nil && remote.deletedAt == nil && remoteTextChanged)
                || (remote.deletedAt != nil && local.deletedAt == nil && localTextChanged)
            if textConflict || editAgainstDeletion {
                let retained: Sticky
                if editAgainstDeletion { retained = local.deletedAt == nil ? local : remote }
                else { retained = remoteIsNewer ? local : remote }
                var copy = retained.duplicated(id: conflictID, at: max(revision(local), revision(remote)))
                copy.conflictSourceID = local.id
                recovered = copy
            }
        }
        merged.frame = local.frame
        merged.isCollapsed = local.isCollapsed
        merged.floatsOnTop = local.floatsOnTop
        merged.appearsOnAllSpaces = local.appearsOnAllSpaces
        merged.updatedAt = max(local.updatedAt, remote.updatedAt)
        return StickyMergeResult(note: merged, recoveredEdit: recovered)
    }

    private static func sameText(_ lhs: Sticky, _ rhs: Sticky) -> Bool {
        lhs.text == rhs.text && lhs.richText == rhs.richText
    }

    private static func revision(_ note: Sticky) -> Date {
        max(note.updatedAt, note.deletedAt ?? .distantPast)
    }
}
