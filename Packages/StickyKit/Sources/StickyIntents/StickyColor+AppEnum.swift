import AppIntents
import Foundation
import StickyDomain

/// A fixed color parameter for Siri and Shortcuts. The shared domain stays
/// independent of App Intents so its storage and migration rules are portable.
extension StickyColor: @retroactive AppEnum {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Color", bundle: .atURL(Bundle.module.bundleURL))
    )

    public static let caseDisplayRepresentations: [StickyColor: DisplayRepresentation] = [
        .clear: DisplayRepresentation(title: LocalizedStringResource("Glass", bundle: .atURL(Bundle.module.bundleURL))),
        .yellow: DisplayRepresentation(title: LocalizedStringResource("Yellow", bundle: .atURL(Bundle.module.bundleURL))),
        .blue: DisplayRepresentation(title: LocalizedStringResource("Blue", bundle: .atURL(Bundle.module.bundleURL))),
        .green: DisplayRepresentation(title: LocalizedStringResource("Green", bundle: .atURL(Bundle.module.bundleURL))),
        .pink: DisplayRepresentation(title: LocalizedStringResource("Pink", bundle: .atURL(Bundle.module.bundleURL))),
        .purple: DisplayRepresentation(title: LocalizedStringResource("Purple", bundle: .atURL(Bundle.module.bundleURL))),
        .gray: DisplayRepresentation(title: LocalizedStringResource("Gray", bundle: .atURL(Bundle.module.bundleURL))),
    ]
}
