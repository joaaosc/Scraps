#if os(iOS)
import StickyDomain
import SwiftUI

struct MobileStickySettingsView: View {
    @AppStorage("defaultStickyColor") private var defaultColor = "clear"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
                        Text("On This Device", bundle: .module)
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
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
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
}
#endif
