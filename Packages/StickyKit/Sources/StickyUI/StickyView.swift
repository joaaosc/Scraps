import AppKit
import StickyDomain
import StickyEditor
import SwiftUI

/// A quiet, readable note with system glass reserved for the window chrome.
struct StickyView: View {
    @Bindable var model: StickyModel
    @State private var isChoosingColor = false
    @State private var showsTags = false
    @State private var appActive = NSApplication.shared.isActive
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            header

            if !model.isCollapsed {
                VStack(spacing: 0) {
                    StickyTextEditor(
                        text: $model.text,
                        richText: $model.richText,
                        startsFocused: model.startsFocused
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 8)

                    if let status = model.status {
                        StickyStatusLine(status: status)
                        if case .failure = status {
                            Button(String(localized: "Keep Edit as Copy", bundle: .module)) { StickyBoard.shared.recoverDraft(model.id) }
                                .font(.caption).padding(.bottom, 8)
                        }
                    }
                }
                .background {
                    // Reading and selecting text need a stable surface. The
                    // system glass remains visible in the slim header/footer.
                    Color(nsColor: .textBackgroundColor)
                    model.color.swatch.opacity(contrast == .increased ? 0.04 : 0.08)
                }

                footer
            }
        }
        .disabled(model.isClosing || model.isArchived)
        .overlay {
            StickyMetalAccent(trigger: model.id.uuidString + model.color.rawValue)
                .environment(\.scenePhase, appActive ? .active : .inactive)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in appActive = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in appActive = false }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(String(localized: "Close", bundle: .module), systemImage: "xmark") {
                model.requestClose()
            }
            .keyboardShortcut("w")
            .help(model.isSessionOnly
                ? String(localized: "Close this sticky", bundle: .module)
                : String(localized: "Move this sticky to Recently Deleted", bundle: .module))

            HStack(spacing: 5) {
                Text(model.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if model.floatsOnTop {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .stickyWindowDrag(onDoubleClick: model.toggleCollapsed)
            .help(String(localized: "Drag to move. Double-click to collapse or expand.", bundle: .module))
            .accessibilityAction(named: Text(String(localized: "Collapse or Expand", bundle: .module))) {
                model.toggleCollapsed()
            }

            Button(
                model.isCollapsed
                    ? String(localized: "Expand", bundle: .module)
                    : String(localized: "Collapse", bundle: .module),
                systemImage: model.isCollapsed ? "chevron.down" : "chevron.up",
                action: model.toggleCollapsed
            )
            .keyboardShortcut("m")
            .help(model.isCollapsed
                ? String(localized: "Expand this sticky", bundle: .module)
                : String(localized: "Collapse this sticky", bundle: .module))

            moreMenu
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    private var moreMenu: some View {
        Menu(String(localized: "Sticky Options", bundle: .module), systemImage: "ellipsis") {
            Button(String(localized: "Color…", bundle: .module), systemImage: "paintpalette") {
                isChoosingColor = true
            }
            Toggle(String(localized: "Favorite", bundle: .module), systemImage: "star", isOn: $model.isPinned)
            Button(String(localized: "Tags…", bundle: .module), systemImage: "tag") { showsTags = true }
            Button(String(localized: "Duplicate", bundle: .module), systemImage: "doc.on.doc") { StickyBoard.shared.duplicate(model.id) }
            Button(String(localized: "Archive", bundle: .module), systemImage: "archivebox") { StickyBoard.shared.setArchived(true, id: model.id) }
            Divider()
            Toggle(String(localized: "Float on Top", bundle: .module), systemImage: "pin", isOn: $model.floatsOnTop)
                .keyboardShortcut("f", modifiers: [.command, .option])
            Toggle(String(localized: "Show on All Spaces", bundle: .module), systemImage: "rectangle.on.rectangle", isOn: $model.appearsOnAllSpaces)
            Divider()
            Button(String(localized: "Copy", bundle: .module), systemImage: "doc.on.doc", action: model.copyText)
                .disabled(model.text.isEmpty)
            Button(String(localized: "Send to Notes", bundle: .module), systemImage: "square.and.arrow.up", action: model.sendToNotes)
                .disabled(!model.canSend)
        }
        .menuIndicator(.hidden)
        .help(String(localized: "Color, window options, and sharing", bundle: .module))
        .popover(isPresented: $showsTags) { StickyTagsEditor(tags: $model.tags) }
        .popover(isPresented: $isChoosingColor, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Sticky Color", bundle: .module))
                    .font(.headline)
                StickyColorPalette(selection: $model.color)
            }
            .padding(16)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.isSessionOnly {
                Label(String(localized: "This session only", bundle: .module), systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "This sticky disappears when Scraps quits", bundle: .module))
            }

            if !model.tags.isEmpty { Text(model.tags.map { "#" + $0 }.joined(separator: " ")).font(.caption2).lineLimit(1) }
            if model.snapshot.conflictSourceID != nil { Image(systemName: "arrow.triangle.branch").accessibilityLabel(Text("Recovered Edit", bundle: .module)) }
            Spacer(minLength: 0)

            if model.isSharing {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel(String(localized: "Sharing sticky", bundle: .module))
            }

            Button(String(localized: "Send to Notes", bundle: .module), systemImage: "square.and.arrow.up", action: model.sendToNotes)
                .labelStyle(.iconOnly)
                .disabled(!model.canSend)
                .help(model.sendUnavailableReason ?? String(localized: "Send this sticky to Notes", bundle: .module))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    model.sendButtonFrame = $0
                }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}
