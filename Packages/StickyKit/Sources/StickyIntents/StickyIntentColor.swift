import AppIntents
import StickyDomain

/// The system's color parameter has local, statically declared cases. Explicit
/// conversion keeps the portable palette independent of intent metadata.
public enum StickyIntentColor: String, AppEnum {
    case clear, yellow, blue, green, pink, purple, gray

    public static let allCases: [StickyIntentColor] = [
        .clear, .yellow, .blue, .green, .pink, .purple, .gray,
    ]

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Color")

    public static let caseDisplayRepresentations: [StickyIntentColor: DisplayRepresentation] = [
        .clear: DisplayRepresentation(title: "Glass"),
        .yellow: DisplayRepresentation(title: "Yellow"),
        .blue: DisplayRepresentation(title: "Blue"),
        .green: DisplayRepresentation(title: "Green"),
        .pink: DisplayRepresentation(title: "Pink"),
        .purple: DisplayRepresentation(title: "Purple"),
        .gray: DisplayRepresentation(title: "Gray"),
    ]

    public init(_ color: StickyColor) {
        self = switch color {
        case .clear: .clear
        case .yellow: .yellow
        case .blue: .blue
        case .green: .green
        case .pink: .pink
        case .purple: .purple
        case .gray: .gray
        }
    }

    public var stickyColor: StickyColor {
        switch self {
        case .clear: .clear
        case .yellow: .yellow
        case .blue: .blue
        case .green: .green
        case .pink: .pink
        case .purple: .purple
        case .gray: .gray
        }
    }
}
