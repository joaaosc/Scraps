import Foundation
import StickyDomain

public enum StickyNavigation: Equatable, Sendable {
    case note(UUID)
    case new
    case library

    public var url: URL {
        var components = URLComponents()
        components.scheme = "scraps"
        switch self {
        case let .note(id): components.host = "note"; components.path = "/\(id.uuidString)"
        case .new: components.host = "new"
        case .library: components.host = "library"
        }
        // All components above are constant ASCII or a generated UUID.
        return components.url!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "scraps", url.query == nil, url.fragment == nil else { return nil }
        switch url.host {
        case "note":
            guard let id = UUID(uuidString: String(url.path.dropFirst())) else { return nil }
            self = .note(id)
        case "new" where url.path.isEmpty || url.path == "/": self = .new
        case "library" where url.path.isEmpty || url.path == "/": self = .library
        default: return nil
        }
    }

    #if canImport(Darwin)
    @MainActor
    public static func handoff(for note: Sticky) -> NSUserActivity {
        let activity = NSUserActivity(activityType: StickyKitIdentity.handoffActivityType)
        activity.title = note.title
        activity.userInfo = ["noteID": note.id.uuidString]
        activity.requiredUserInfoKeys = ["noteID"]
        activity.targetContentIdentifier = note.id.uuidString
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.isEligibleForPublicIndexing = false
        #if os(iOS)
        activity.isEligibleForPrediction = false
        #endif
        return activity
    }

    public static func noteID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == StickyKitIdentity.handoffActivityType,
              let value = activity.userInfo?["noteID"] as? String else { return nil }
        return UUID(uuidString: value)
    }
    #endif
}
