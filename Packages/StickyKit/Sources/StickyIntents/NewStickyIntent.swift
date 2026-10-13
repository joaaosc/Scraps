import AppIntents
import StickyUI

/// Puts a new sticky on screen, holding the text given or empty and ready to
/// type in.
public struct NewStickyIntent: AppIntent {
    public static let title: LocalizedStringResource = "New Sticky"
    public static let description = IntentDescription(
        "Opens a new sticky, with the text you give it or empty and ready to type in."
    )
    /// A sticky is a window, so the app comes forward for it to be typed into.
    public static let supportedModes: IntentModes = [.foreground(.immediate)]

    /// Optional, so the action runs straight from Spotlight without a question.
    @Parameter(title: "Text")
    public var text: String?

    public static var parameterSummary: some ParameterSummary {
        Summary("New sticky with \(\.$text)")
    }

    public init() {}

    public init(text: String?) {
        self.text = text
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try await StickyBoard.shared.addSticky(text: trimmed)
        return .result()
    }
}
