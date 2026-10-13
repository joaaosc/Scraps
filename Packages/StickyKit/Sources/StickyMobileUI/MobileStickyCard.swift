#if os(iOS)
import StickyDomain
import StickyEditor
import SwiftUI

struct MobileStickyCard: View {
    let sticky: Sticky
    let sessionOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sticky.isEmpty ? String(localized: "New Sticky", bundle: .module) : sticky.title)
                .font(.headline)
                .lineLimit(2)
            Text(sticky.bodyPreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                Text(sticky.updatedAt, style: .date)
                Spacer()
                if sessionOnly { Image(systemName: "clock") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(sticky.color.mobileSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08), lineWidth: 1) }
        .overlay { StickyMetalAccent(trigger: sticky.id.uuidString + sticky.color.rawValue) }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityValue(sessionOnly ? Text("This Session", bundle: .module) : Text("Saved", bundle: .module))
        .accessibilityHint(sticky.color.localizedName)
    }
}
#endif
