#if os(iOS)
import StickyDomain
import StickyEditor
import StickyStorage
import SwiftUI

struct MobileStickyDetailView: View {
    @Bindable var library: MobileStickyLibrary
    let id: UUID
    @State private var showsTags = false
    @Environment(\.dismiss) private var dismiss

    private var text: Binding<String> {
        Binding(get: { library.sticky(id: id)?.text ?? "" }, set: {
            library.edit(id: id, text: $0, richText: library.sticky(id: id)?.richText)
        })
    }

    private var richText: Binding<StickyRichText?> {
        Binding(get: { library.sticky(id: id)?.richText }, set: {
            library.edit(id: id, text: library.sticky(id: id)?.text ?? "", richText: $0)
        })
    }

    private var color: Binding<StickyColor> {
        Binding(get: { library.sticky(id: id)?.color ?? .clear }, set: {
            library.setColor($0, id: id)
        })
    }

    var body: some View {
        Group {
            if let sticky = library.sticky(id: id) {
                VStack(spacing: 0) {
                    StickyTextEditor(text: text, richText: richText, startsFocused: sticky.isEmpty)
                        .disabled(library.deletingIdentifiers.contains(id))
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    HStack(spacing: 8) {
                        if library.isSessionOnly(id: id) {
                            Label { Text("This Session", bundle: .module) } icon: { Image(systemName: "clock") }
                        }
                        if !sticky.tags.isEmpty { Text(sticky.tags.map { "#" + $0 }.joined(separator: " ")).lineLimit(1) }
                        if sticky.conflictSourceID != nil { Image(systemName: "arrow.triangle.branch").accessibilityLabel(Text("Recovered Edit", bundle: .module)) }
                        Spacer()
                        saveStatus
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .background(sticky.color.mobileSurface)
                .navigationTitle(sticky.title)
                .navigationBarTitleDisplayMode(.inline)
                .userActivity(StickyKitIdentity.handoffActivityType, isActive: !library.isSessionOnly(id: id)) { activity in
                    activity.title = sticky.title
                    activity.userInfo = ["noteID": sticky.id.uuidString]
                    activity.requiredUserInfoKeys = ["noteID"]
                    activity.targetContentIdentifier = sticky.id.uuidString
                    activity.isEligibleForHandoff = true
                    activity.isEligibleForSearch = false
                    activity.isEligibleForPublicIndexing = false
                    activity.isEligibleForPrediction = false
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Menu {
                            Button { library.setPinned(!sticky.isPinned, id: id) } label: {
                                Label(sticky.isPinned ? String(localized: "Remove Favorite", bundle: .module) : String(localized: "Add Favorite", bundle: .module), systemImage: "star")
                            }
                            Button { showsTags = true } label: {
                                Label { Text("Tags…", bundle: .module) } icon: { Image(systemName: "tag") }
                            }
                            Button { Task { if let copy = await library.duplicate(id: id) { library.openSticky(id: copy.id) } } } label: {
                                Label { Text("Duplicate", bundle: .module) } icon: { Image(systemName: "doc.on.doc") }
                            }
                            Button { library.setArchived(!sticky.isArchived, id: id); Task { await library.flush(); dismiss() } } label: {
                                Label(sticky.isArchived ? String(localized: "Unarchive", bundle: .module) : String(localized: "Archive", bundle: .module), systemImage: "archivebox")
                            }
                            Divider()
                            Picker(selection: color) {
                                ForEach(StickyColor.allCases) { choice in
                                    Text(choice.localizedName).tag(choice)
                                }
                            } label: {
                                Text("Sticky Color", bundle: .module)
                            }
                        } label: {
                            Label { Text("Sticky Options", bundle: .module) } icon: { Image(systemName: "ellipsis.circle") }
                        }
                        .accessibilityLabel(Text("Sticky Options", bundle: .module))
                        ShareLink(item: StickyShareDocument(sticky: sticky), preview: SharePreview(LocalizedStringResource("\(sticky.title)"))) {
                            Label { Text("Share", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
                        }
                        .disabled(sticky.isEmpty)
                        Button(role: .destructive) {
                            Task { if await library.moveToTrash(id: id) { dismiss() } }
                        } label: {
                            Label { Text("Delete", bundle: .module) } icon: { Image(systemName: "trash") }
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label { Text("Sticky Unavailable", bundle: .module) } icon: { Image(systemName: "note.text") }
                } description: {
                    Text("You can recover deleted stickies from Recently Deleted.", bundle: .module)
                }
            }
        }
        .popover(isPresented: $showsTags) {
            StickyTagsEditor(tags: Binding(get: { library.sticky(id: id)?.tags ?? [] }, set: { library.setTags($0, id: id) }))
        }
        .onDisappear { Task { await library.flush() } }
    }

    @ContentBuilder
    private var saveStatus: some View {
        switch library.saveStates[id] ?? .saved {
        case .saved:
            Label { Text("Saved", bundle: .module) } icon: { Image(systemName: "checkmark") }
                .accessibilityLabel(Text("All Changes Saved", bundle: .module))
        case .saving:
            Label { Text("Saving…", bundle: .module) } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
        case .failed:
            Button { Task { await library.retrySave(id: id) } } label: {
                Label { Text("Retry Save", bundle: .module) } icon: { Image(systemName: "exclamationmark.circle") }
            }
            .foregroundStyle(.red)
        }
    }
}
#endif
