import SwiftUI

/// The corner every layer of a sticky shares, so the panel, the content clip
/// and the border never drift apart by a point.
public enum StickyGlassMetrics {
    public static let cornerRadius: CGFloat = 18

    public static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius)
    }
}

/// What a sticky draws over its AppKit glass: nothing at rest, a plate only
/// when an accessibility setting asks for one, and a border under Increase
/// Contrast.
///
/// The material itself belongs to `StickyGlassHostingView`, the
/// `NSGlassEffectView` the SwiftUI tree is hosted in. Drawing a second
/// `.glassEffect` here would put glass on glass. The *regular* Liquid Glass
/// variant already blurs and adjusts the luminosity of what is behind it to
/// keep text legible, so a plate at rest would only turn it into a milky pane.
///
/// The plate is drawn with `.ignoresSafeArea()`: the panel is `.titled` with
/// `.fullSizeContentView`, and without it the plate stops short of the hidden
/// title bar's safe-area inset, leaving a band across the top.
struct StickyGlassSurface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background {
                // Reduce Transparency asks for an opaque surface, and gets one
                // here even if the glass behind already turned solid: the
                // guarantee should not depend on how the material degrades.
                // Increase Contrast raises the plate towards opaque: the
                // refraction is decoration, the text is not.
                Color(nsColor: .windowBackgroundColor)
                    .opacity(reduceTransparency ? 1 : (contrast == .increased ? 0.85 : 0))
                    .ignoresSafeArea()
            }
            .clipShape(StickyGlassMetrics.shape)
            .overlay {
                // Increase Contrast asks for visible edges; the glass's own
                // specular rim is too faint to count as one.
                if contrast == .increased {
                    StickyGlassMetrics.shape
                        .strokeBorder(.primary.opacity(0.45), lineWidth: 1)
                        .ignoresSafeArea()
                }
            }
    }
}

extension View {
    /// Wraps the view in a sticky's accessibility layer. The glass itself
    /// comes from the panel's `StickyGlassHostingView`.
    func stickyGlassSurface() -> some View {
        StickyGlassSurface { self }
    }
}
