#if os(iOS)
import StickyDomain
import SwiftUI

struct MobileRecentlyDeletedView: View {
    @Bindable var library: MobileStickyLibrary
    @State private var pendingDeletion: Sticky?
    @State private var workingIdentifiers: Set<UUID> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if library.recentlyDeleted.isEmpty {
                    ContentUnavailableView {
                        Label { Text("No Deleted Stickies", bundle: .module) } icon: { Image(systemName: "trash") }
                    } description: {
                        Text("Deleted stickies are kept here for 30 days.", bundle: .module)
                    }
                } else {
                    List {
                        Section {
                            ForEach(library.recentlyDeleted) { sticky in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(sticky.isEmpty ? String(localized: "New Sticky", bundle: .module) : sticky.title)
                                        .font(.headline)
                                        .lineLimit(2)
                                    if let deletedAt = sticky.deletedAt {
                                        Text(deletedAt, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        Button { restore(sticky) } label: {
                                            Label { Text("Recover", bundle: .module) } icon: { Image(systemName: "arrow.uturn.backward") }
                                        }
                                        Spacer()
                                        Button(role: .destructive) { pendingDeletion = sticky } label: {
                                            Label { Text("Delete", bundle: .module) } icon: { Image(systemName: "trash") }
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 4)
                                .disabled(workingIdentifiers.contains(sticky.id))
                                .swipeActions(edge: .leading) {
                                    Button { restore(sticky) } label: {
                                        Label { Text("Recover", bundle: .module) } icon: { Image(systemName: "arrow.uturn.backward") }
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { pendingDeletion = sticky } label: {
                                        Label { Text("Delete", bundle: .module) } icon: { Image(systemName: "trash") }
                                    }
                                }
                            }
                        } footer: {
                            Text("Deleted stickies are kept here for 30 days.", bundle: .module)
                        }
                    }
                }
            }
            .navigationTitle(Text("Recently Deleted", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
            .confirmationDialog(Text("Delete Sticky Permanently?", bundle: .module), item: $pendingDeletion, titleVisibility: .visible) { sticky in
                Button(role: .destructive) {
                    workingIdentifiers.insert(sticky.id)
                    Task {
                        await library.permanentlyDelete(id: sticky.id)
                        workingIdentifiers.remove(sticky.id)
                    }
                } label: {
                    Text("Delete Permanently", bundle: .module)
                }
                Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            } message: { _ in
                Text("This sticky cannot be recovered after it is permanently deleted.", bundle: .module)
            }
        }
    }

    private func restore(_ sticky: Sticky) {
        guard !workingIdentifiers.contains(sticky.id) else { return }
        workingIdentifiers.insert(sticky.id)
        Task {
            await library.restore(id: sticky.id)
            workingIdentifiers.remove(sticky.id)
        }
    }
}
#endif
