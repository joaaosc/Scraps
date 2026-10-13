#if os(iOS)
import StickyDomain
import StickySync
import SwiftUI

struct MobileStickySettingsView: View {
    @AppStorage("defaultStickyColor") private var defaultColor = "clear"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                StickySyncSettingsSection()
                Section {
                    Picker(selection: $defaultColor) {
                        ForEach(StickyColor.allCases, id: \.self) { color in
                            Text(color.localizedName).tag(color.rawValue)
                        }
                    } label: {
                        Text("Default Color", bundle: .module)
                    }
                } header: {
                    Text("New Stickies", bundle: .module)
                }
                Section {
                    LabeledContent {
                        Text(StickyCloudSync.shared.isEnabled ? LocalizedStringKey("On This Device and iCloud") : LocalizedStringKey("On This Device"), bundle: .module)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("Storage", bundle: .module)
                    }
                } header: {
                    Text("Your Stickies", bundle: .module)
                } footer: {
                    Text("Stickies save automatically on this device. Share a sticky to keep it in Apple Notes or send it to another app.", bundle: .module)
                }
                Section {
                    Text("Session stickies stay in memory and disappear when Scraps quits. Use Share to keep anything you need.", bundle: .module)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("This Session Only", bundle: .module)
                }
                Section {
                    LabeledContent {
                        Text(version)
                    } label: {
                        Text("Version", bundle: .module)
                    }
                }
            }
            .navigationTitle(Text("Settings", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
        }
    }

    private var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(marketing) (\(build))"
    }
}
#endif
