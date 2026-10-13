import AppKit
import SwiftUI

/// The AppKit owner of a sticky's Liquid Glass.
///
/// ```
/// NSPanel
///   └── StickyGlassHostingView (NSGlassEffectView: material, refraction, corners)
///         └── contentView: NSHostingController.view (the SwiftUI tree)
/// ```
///
/// Two details are load-bearing:
///
/// - The SwiftUI tree is the glass's `contentView`. That is the placement
///   AppKit documents as inside the effect; a subview added beside it is not.
///   The glass wraps it in its own holder and keeps it the size of the glass,
///   so no frame syncing is needed here.
/// - `sizingOptions = []`. The SwiftUI tree does not impose its size on the
///   glass or the window: a panel the person resizes would otherwise have its
///   edge fought over by the content's intrinsic size on every update.
///
/// The SwiftUI side never draws a material of its own (see
/// `StickyGlassSurface`): one glass per panel, owned here. No entitlement is
/// involved — this is a view hierarchy inside the app's own windows.
public final class StickyGlassHostingView<Content: View>: NSGlassEffectView {
    private let hostingController: NSHostingController<Content>

    public init(
        rootView: Content,
        cornerRadius: CGFloat = StickyGlassMetrics.cornerRadius
    ) {
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = []
        hostingController = controller
        super.init(frame: .zero)

        style = .regular
        self.cornerRadius = cornerRadius
        // No tint: Liquid Glass has no colour of its own and takes it from
        // what is behind it.
        tintColor = nil
        contentView = controller.view
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }
}
