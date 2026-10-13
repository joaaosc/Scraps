#if os(iOS)
import StickyDomain
import StickyEditor
import SwiftUI

struct MobileStickyRow: View {
    let sticky: Sticky
    let sessionOnly: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5)
                .fill(sticky.color.mobileSurface)
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
                .frame(width: 24, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(sticky.isEmpty ? String(localized: "New Sticky", bundle: .module) : sticky.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(sticky.bodyPreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(sticky.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if sessionOnly {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("This Session", bundle: .module))
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
