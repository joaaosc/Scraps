#if os(iOS)
import StickyDomain
import StickyEditor
import SwiftUI

extension Sticky {
    var bodyPreview: String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
