import StickyDomain
import StickyEditor
import StickyUI
import SwiftUI

struct ScrapsLibraryView: View {
    private var board: StickyBoard { .shared }
    @State private var collection = StickyCollection.notes
    @State private var selection: UUID?
    @State private var search = ""
    @State private var tag: String?
    @State private var showsTags = false
    private var results: [Sticky] { collection.notes(in: board.libraryStickies, search: search, tag: tag) }
    private var allTags: [String] {
        Array(Set(board.libraryStickies.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    ForEach(StickyCollection.allCases) { item in
                        Button { collection = item; tag = nil; selection = nil } label: {
                            Label(item.localizedName, systemImage: item.systemImage)
                                .foregroundStyle(collection == item && tag == nil ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !allTags.isEmpty {
                    Section("Tags") {
                        ForEach(allTags, id: \.self) { value in
                            Button { tag = value; collection = .notes; selection = nil } label: {
                                Label("#" + value, systemImage: "tag")
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    Button("Recently Deleted", systemImage: "trash") { ScrapsUtilityWindows.shared.showRecentlyDeleted() }
                        .buttonStyle(.plain)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        } content: {
            List(selection: $selection) {
                ForEach(results) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(note.title).font(.headline).lineLimit(1)
                            if note.isPinned { Image(systemName: "star.fill").accessibilityLabel("Favorite") }
                            if board.isSessionOnly(note.id) { Image(systemName: "clock").accessibilityLabel("This Session") }
                        }
                        Text(note.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Text(note.updatedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(note.id)
                    .contextMenu { actions(note) }
                }
            }
            .overlay { if results.isEmpty { ContentUnavailableView.search(text: search) } }
            .navigationTitle(tag.map { "#" + $0 } ?? collection.localizedName)
            .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            if let id = selection, let note = board.currentSnapshot(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(note.title).font(.title).textSelection(.enabled)
                        if note.conflictSourceID != nil {
                            Label("Recovered Edit", systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(StickyRichTextBridge.attributedText(text: note.text, richText: note.richText))
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        if !note.tags.isEmpty { Text(note.tags.map { "#" + $0 }.joined(separator: " ")).foregroundStyle(.secondary) }
                        HStack {
                            Button(note.isArchived ? String(localized: "Unarchive") : String(localized: "Open Sticky")) {
                                if note.isArchived { board.setArchived(false, id: id) }
                                else { Task { await board.openStoredSticky(id) } }
                            }.buttonStyle(.borderedProminent)
                            ShareLink(item: StickyShareDocument(sticky: note), preview: SharePreview(LocalizedStringResource("\(note.title)")))
                                .disabled(note.isEmpty)
                            Menu("Sticky Options", systemImage: "ellipsis") { actions(note) }
                        }
                    }.padding(24)
                }
            } else {
                ContentUnavailableView("Select a Sticky", systemImage: "note.text", description: Text("Your thoughts, together in one place."))
            }
        }
        .searchable(text: $search, prompt: Text("Search Stickies"))
        .toolbar {
            Button("New Sticky", systemImage: "square.and.pencil") { board.newSticky() }
        }
        .popover(isPresented: $showsTags) {
            StickyTagsEditor(tags: Binding(get: { selection.flatMap { board.currentSnapshot($0)?.tags } ?? [] }, set: { value in
                if let selection { board.setTags(value, id: selection) }
            }))
        }
    }
    @ViewBuilder private func actions(_ note: Sticky) -> some View {
        Button(note.isPinned ? String(localized: "Remove Favorite") : String(localized: "Add Favorite"), systemImage: "star") {
            board.setPinned(!note.isPinned, id: note.id)
        }
        Button("Tags…", systemImage: "tag") { selection = note.id; showsTags = true }
        Button("Duplicate", systemImage: "doc.on.doc") { board.duplicate(note.id) }
        Button(note.isArchived ? String(localized: "Unarchive") : String(localized: "Archive"), systemImage: "archivebox") {
            board.setArchived(!note.isArchived, id: note.id)
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { board.moveToTrash(note.id) }
    }
}
