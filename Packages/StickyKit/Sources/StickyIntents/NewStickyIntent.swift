import AppIntents
import Foundation
import StickyDomain

/// Puts a new sticky on screen, holding the text given or empty and ready to
/// type in.
public struct NewStickyIntent: AppIntent {
    public static let title: LocalizedStringResource = "New Sticky"
    public static let description = IntentDescription(
        "Opens a new sticky, with the text you give it or empty and ready to type in."
    )
    /// A sticky is a window, so the app comes forward for it to be typed into.
    public static let supportedModes: IntentModes = [.foreground(.immediate)]

    /// Optional, so Siri and Shortcuts can also create an empty sticky.
    @Parameter(title: "Text")
    public var text: String?

    /// Omitted colors use the person's default. This parameter remains a
    /// Siri/Shortcuts option and does not expand the fixed Spotlight catalog.
    @Parameter(title: "Color")
    public var color: StickyIntentColor?

    public static var parameterSummary: some ParameterSummary {
        Summary("New sticky with \(\.$text)") {
            \.$color
        }
    }

    public init() {}

    public init(text: String?, color: StickyColor? = nil) {
        self.text = text
        self.color = color.map { StickyIntentColor($0) }
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try await StickyActionRouter.perform(.newSticky, text: trimmed, color: color?.stickyColor)
        return .result()
    }
}
