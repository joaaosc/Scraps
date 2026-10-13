import Foundation

/// A small paper-inspired palette. Clear uses the platform's glass appearance.
public enum StickyColor: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case clear, yellow, blue, green, pink, purple, gray

    public var id: Self { self }

    public var localizedName: String {
        let key: String
        switch self {
        case .clear: key = "Glass"
        case .yellow: key = "Yellow"
        case .blue: key = "Blue"
        case .green: key = "Green"
        case .pink: key = "Pink"
        case .purple: key = "Purple"
        case .gray: key = "Gray"
        }
        return NSLocalizedString(key, bundle: .module, comment: "Sticky color")
    }
}
