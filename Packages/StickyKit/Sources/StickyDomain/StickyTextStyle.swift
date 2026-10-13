import Foundation

public enum StickyTextStyle: String, Codable, CaseIterable, Sendable {
    case body, title, heading, caption, code
    public var localizedName: String {
        let name: String
        switch self {
        case .body: name = "Body"
        case .title: name = "Title"
        case .heading: name = "Heading"
        case .caption: name = "Caption"
        case .code: name = "Code"
        }
        return NSLocalizedString(name, bundle: .module, comment: "Semantic text style")
    }
}
