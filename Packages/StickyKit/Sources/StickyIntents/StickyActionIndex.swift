import AppIntents
import CoreSpotlight
import StickyDomain

/// The only search index owned by Scraps. A task queue serializes startup
/// rebuilds and system reindex requests across suspensions in Core Spotlight.
public actor StickyActionIndex {
    public static let shared = StickyActionIndex()
    public static let name = "StickyActions"

    private var lastUpdate: Task<Void, Error>?

    private init() {}

    /// Called once the app starts. Removing this entity type first clears
    /// obsolete action IDs left by earlier app versions, then donates exactly
    /// the four actions with descending priorities.
    public static func rebuild() async throws {
        try await shared.enqueue(StickyAction.allCases, rebuilding: true)
    }

    func reindex(_ actions: [StickyAction]) async throws {
        try await enqueue(actions, rebuilding: false)
    }

    private func enqueue(_ actions: [StickyAction], rebuilding: Bool) async throws {
        let previous = lastUpdate
        let update = Task {
            // A failed update must not prevent the next reindex from repairing
            // the index. Each caller still receives its own update's failure.
            try? await previous?.value
            let index = CSSearchableIndex(name: Self.name)
            if rebuilding {
                try await index.deleteAppEntities(ofType: StickyActionEntity.self)
            }
            for action in actions {
                try await index.indexAppEntities(
                    [StickyActionEntity(action: action)],
                    priority: action.priority
                )
            }
        }
        lastUpdate = update
        try await update.value
    }
}
