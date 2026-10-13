#if os(iOS)
import StickyDomain
import StickyEditor
import SwiftUI

extension StickyColor {
    var mobileSurface: Color {
        switch self {
        case .clear: Color(uiColor: .secondarySystemGroupedBackground)
        case .yellow: Color.yellow.opacity(0.16)
        case .blue: Color.blue.opacity(0.12)
        case .green: Color.green.opacity(0.12)
        case .pink: Color.pink.opacity(0.12)
        case .purple: Color.purple.opacity(0.12)
        case .gray: Color.gray.opacity(0.13)
        }
    }
}
#endif
