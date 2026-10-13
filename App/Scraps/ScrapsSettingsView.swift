import StickyDomain
import StickyEditor
import StickyUI
import SwiftUI

struct ScrapsSettingsView: View {
    @AppStorage("defaultStickyColor") private var color = StickyColor.clear.rawValue
    @AppStorage("defaultFloatsOnTop") private var floatsOnTop = true
    @AppStorage("defaultAppearsOnAllSpaces") private var allSpaces = false
    @AppStorage("globalShortcutEnabled") private var globalShortcut = false
    @State private var shortcutError: String?

    var body: some View {
        Form {
            Section("New stickies") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Default color")
                    StickyColorPalette(selection: Binding(
                        get: { StickyColor(rawValue: color) ?? .clear },
                        set: { color = $0.rawValue }
                    ))
                }
                Toggle("Float on Top", isOn: $floatsOnTop)
                Toggle("Show on All Desktops", isOn: $allSpaces)
                Text("Defaults apply to new stickies. Change any existing sticky from its menu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Quick capture") {
                Toggle("Enable global keyboard shortcut", isOn: $globalShortcut)
                    .onChange(of: globalShortcut) { _, enabled in
                        do {
                            try StickyBoard.shared.setGlobalShortcutEnabled(enabled)
                            shortcutError = nil
                        } catch {
                            globalShortcut = false
                            shortcutError = error.localizedDescription
                        }
                    }
                Text("Create a sticky from any app with ⌃⌥⌘N.")
                    .font(.caption).foregroundStyle(.secondary)
                if let shortcutError { Text(shortcutError).foregroundStyle(.red) }
            }
            Section("Your notes") {
                Button("Recently Deleted…") { ScrapsUtilityWindows.shared.showRecentlyDeleted() }
                Button("Send All to Notes…") { StickyBoard.shared.exportAllToNotes() }
                    .disabled(!StickyBoard.shared.hasOpenStickies)
                Text("Closed stickies can be restored for 30 days. Session stickies disappear when you quit. Notes stay on this device.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Version", value: version)
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(marketing) (\(build))"
    }
}
