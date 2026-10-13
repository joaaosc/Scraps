import AppIntents
import Foundation

/// Spotlight opens an indexed action using this intent. Foreground execution
/// lets the app finish connecting its store before a sticky is created.
public struct OpenStickyActionIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Action"
    public static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter(title: "Action")
    public var target: StickyActionEntity

    public init() {}

    public init(target: StickyActionEntity) {
        self.target = target
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        try await StickyActionRouter.perform(target.action)
        return .result()
    }
}
