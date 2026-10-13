import StickyDomain
import SwiftUI

/// The same small, labelled palette in the desktop sticky and the mobile app.
public struct StickyColorPalette: View {
    @Binding private var selection: StickyColor
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 28

    public init(selection: Binding<StickyColor>) {
        _selection = selection
    }

    public var body: some View {
        Group {
            #if os(iOS)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumCellWidth))], spacing: 4) {
                swatches
            }
            #else
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { swatches }
                    .fixedSize(horizontal: true, vertical: false)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumCellWidth))], spacing: 6) {
                    swatches
                }
            }
            #endif
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Sticky color", bundle: .module))
    }

    private var swatches: some View {
        ForEach(StickyColor.allCases) { color in
            Button {
                selection = color
            } label: {
                VStack(spacing: 2) {
                    Circle()
                        .fill(color == .clear ? Color.primary.opacity(0.04) : color.swatch.opacity(0.72))
                        .overlay {
                            Circle().strokeBorder(
                                Color.primary.opacity(selection == color || contrast == .increased ? 0.8 : 0.2),
                                lineWidth: selection == color ? 2 : 1
                            )
                        }
                        .overlay {
                            if selection == color {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary)
                            } else if color == .clear {
                                Image(systemName: "circle.slash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: diameter, height: diameter)
                        #if os(iOS)
                        .padding(8)
                        .frame(minWidth: 44, minHeight: 44)
                        #else
                        .padding(3)
                        #endif
                        .contentShape(.circle)
                    if differentiateWithoutColor {
                        Text(color.localizedName)
                            .font(.caption2)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(color.localizedName)
            .accessibilityLabel(color.localizedName)
            .accessibilityValue(selection == color ? String(localized: "Selected", bundle: .module) : "")
            .accessibilityAddTraits(selection == color ? .isSelected : [])
        }
    }

    private var minimumCellWidth: CGFloat {
        #if os(iOS)
        let padding: CGFloat = 16
        #else
        let padding: CGFloat = 6
        #endif
        return max(differentiateWithoutColor ? 70 : 44, diameter + padding)
    }
}

public extension StickyColor {
    var swatch: Color {
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
