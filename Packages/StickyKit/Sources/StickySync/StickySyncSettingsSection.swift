import SwiftUI

public struct StickySyncSettingsSection: View {
    @State private var sync = StickyCloudSync.shared

    public init() {}

    public var body: some View {
        Section {
            Toggle(String(localized: "Use iCloud", bundle: .module), isOn: Binding(
                get: { sync.isEnabled }, set: { sync.setEnabled($0) }
            ))
            Label(sync.statusMessage, systemImage: sync.isEnabled ? "icloud" : "icloud.slash")
                .foregroundStyle(.secondary)
                .font(.callout)
            if sync.isEnabled {
                Button(String(localized: "Sync Now", bundle: .module), systemImage: "arrow.triangle.2.circlepath") {
                    Task { await sync.synchronize() }
                }
                .disabled(sync.status == .syncing)
            }
            if let date = sync.lastSyncedAt {
                LabeledContent {
                    Text(date, style: .relative)
                } label: {
                    Text("Last synced", bundle: .module)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Across your devices", bundle: .module)
        } footer: {
            Text("Sync persistent notes, formatting, colors and tags between your Mac, iPhone and iPad. Session notes stay on this device.", bundle: .module)
        }
    }
}
