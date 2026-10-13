import AppIntents
import CoreSpotlight
import Foundation
import StickyDomain

/// A command in Scraps' fixed Spotlight list, never a person's sticky.
/// Keeping only a `StickyAction` here prevents note text, attachments, and
/// session contents from entering the search index.
public struct StickyActionEntity: IndexedEntity {
    public static let persistentIdentifier = "StickyAction"
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Action"
    )
    public static let defaultQuery = StickyActionQuery()

    public let action: StickyAction
    public var id: String { action.rawValue }

    public init(action: StickyAction) {
        self.action = action
    }

    public var localizedTitle: LocalizedStringResource {
        switch action {
        case .newSticky:
            "New Sticky"
        case .newSessionSticky:
            "New Sticky (This Session Only)"
        case .newStickyInColor:
            "New Sticky in Color…"
        case .settings:
            "Settings"
        }
    }

    public var displayRepresentation: DisplayRepresentation {
        return DisplayRepresentation(
            title: localizedTitle,
            image: .init(systemName: action.symbol)
        )
    }

    /// Siri's language and the app's preferred language can differ. Search
    /// recognizes every translation shipped by the app, while the displayed
    /// title continues to use the person's current language.
    var searchTitles: [String] {
        var resource = localizedTitle
        var titles = [action.title, String(localized: resource)]
        for language in Bundle.main.localizations where language != "Base" {
            resource.locale = Locale(identifier: language)
            titles.append(String(localized: resource))
        }
        return Array(Set(titles)).sorted()
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.rankingHint = NSNumber(value: action.priority)
        attributes.keywords = searchTitles
        return attributes
    }

    /// Compatibility path for Spotlight launches delivered as a user
    /// activity. Decode Apple's entity identifier rather than guessing its
    /// serialized format or accepting identifiers belonging to another type.
    public static func action(from activity: NSUserActivity) -> StickyAction? {
        let identifier: EntityIdentifier?
        if let associated = activity.appEntityIdentifier {
            identifier = associated
        } else if activity.activityType == CSSearchableItemActionType,
                  let value = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
            identifier = EntityIdentifier(activityIdentifier: value)
        } else {
            return nil
        }
        guard let identifier,
              identifier.entityType == StickyActionEntity.self else { return nil }
        return StickyAction(rawValue: identifier.identifier)
    }
}

/// All lookup paths use the same fixed catalog; none fetch a sticky store.
public struct StickyActionQuery: EntityStringQuery, IndexedEntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [StickyActionEntity] {
        StickyAction.identified(by: identifiers).map(StickyActionEntity.init(action:))
    }

    public func entities(matching string: String) async throws -> [StickyActionEntity] {
        let localizedNames = Dictionary(uniqueKeysWithValues: StickyAction.allCases.map { action in
            (action, StickyActionEntity(action: action).searchTitles)
        })
        return Self.matchingActions(string, localizedNames: localizedNames)
            .map(StickyActionEntity.init(action:))
    }

    static func matchingActions(
        _ query: String,
        localizedNames: [StickyAction: [String]]
    ) -> [StickyAction] {
        var matching = Set(StickyAction.matching(query))
        for action in StickyAction.allCases where !matching.contains(action) {
            for name in localizedNames[action] ?? [] {
                if StickyAction.matching(query, localizedTitles: [action: name]).contains(action) {
                    matching.insert(action)
                    break
                }
            }
        }
        return StickyAction.allCases.filter { matching.contains($0) }
    }

    public func suggestedEntities() async throws -> [StickyActionEntity] {
        StickyAction.allCases.map(StickyActionEntity.init(action:))
    }

    public func reindexEntities(
        for identifiers: [String],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        try await StickyActionIndex.shared.reindex(StickyAction.identified(by: identifiers))
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await StickyActionIndex.rebuild()
    }
}
