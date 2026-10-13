import AppIntents
import Foundation

/// Brings every sticky in front of whatever is covering it.
public struct ShowStickiesIntent: AppIntent {
    public static let title = LocalizedStringResource("Show All Stickies", bundle: .atURL(Bundle.module.bundleURL))
    public static let description = IntentDescription(
        LocalizedStringResource("Brings every sticky to the front.", bundle: .atURL(Bundle.module.bundleURL))
    )
    public static let supportedModes: IntentModes = [.foreground(.immediate)]

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        try await StickyActionRouter.showAll()
        return .result()
    }
}
