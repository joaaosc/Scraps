#if os(iOS)
import StickyDomain
import StickyEditor
import SwiftUI

public struct MobileStickyRootView: View {
    @Bindable private var library: MobileStickyLibrary
    @State private var search = ""
    @State private var creating = false
    @AppStorage("mobileShowsList") private var showsList = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(library: MobileStickyLibrary) {
        self.library = library
    }

    private var results: [Sticky] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.stickies.filter { query.isEmpty || $0.text.localizedStandardContains(query) }
    }

    public var body: some View {
        NavigationStack(path: $library.navigation) {
            Group {
                if !library.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(Text("Loading Stickies", bundle: .module))
                } else if library.stickies.isEmpty {
                    ContentUnavailableView {
                        Label { Text("A Little Space for Your Thoughts", bundle: .module) } icon: { Image(systemName: "note.text") }
                    } description: {
                        Text("Keep a quick thought, a list, or something you need close by.", bundle: .module)
                    } actions: {
                        Button { createSticky() } label: { Text("New Sticky", bundle: .module) }
                            .buttonStyle(.borderedProminent)
                            .disabled(creating || !library.isAvailable)
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if showsList || dynamicTypeSize.isAccessibilitySize {
                    notesList
                } else {
                    notesGrid
                }
            }
            .navigationTitle("Scraps")
            .searchable(text: $search, prompt: Text("Search Stickies", bundle: .module))
            .toolbar {
                ToolbarOverflowMenu {
                    Button { showsList.toggle() } label: {
                        Label {
                            Text(showsList ? LocalizedStringKey("View as Grid") : LocalizedStringKey("View as List"), bundle: .module)
                        } icon: { Image(systemName: showsList ? "square.grid.2x2" : "list.bullet") }
                    }
                    Button { library.presentation = .recentlyDeleted } label: {
                        Label { Text("Recently Deleted", bundle: .module) } icon: { Image(systemName: "trash") }
                    }
                    Button { library.presentation = .settings } label: {
                        Label { Text("Settings", bundle: .module) } icon: { Image(systemName: "gearshape") }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { createSticky() } label: {
                            Label { Text("New Sticky", bundle: .module) } icon: { Image(systemName: "note.text.badge.plus") }
                        }
                        Button { createSticky(sessionOnly: true) } label: {
                            Label { Text("New Sticky (This Session Only)", bundle: .module) } icon: { Image(systemName: "clock") }
                        }
                        Button { library.presentation = .colorPicker } label: {
                            Label { Text("New Sticky in Color…", bundle: .module) } icon: { Image(systemName: "paintpalette") }
                        }
                    } label: {
                        Label { Text("New Sticky", bundle: .module) } icon: { Image(systemName: "square.and.pencil") }
                    } primaryAction: {
                        createSticky()
                    }
                    .keyboardShortcut("n")
                    .disabled(creating || !library.isAvailable)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                MobileStickyDetailView(library: library, id: id)
            }
            .refreshable { await library.reload() }
        }
        .sheet(item: $library.presentation) { presentation in
            switch presentation {
            case .recentlyDeleted: MobileRecentlyDeletedView(library: library)
            case .settings: MobileStickySettingsView()
            case .colorPicker: MobileNewColorView(library: library)
            }
        }
        .alert("Scraps", item: $library.notice) { _ in
        } message: { notice in
            Text(notice.message)
        }
        .task { await library.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await library.reload() }
            } else {
                MobileBackgroundSave.flush(library)
            }
        }
    }

    private var notesGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 300), spacing: 16)], spacing: 16) {
                ForEach(results) { sticky in
                    NavigationLink(value: sticky.id) {
                        MobileStickyCard(sticky: sticky, sessionOnly: library.isSessionOnly(id: sticky.id))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { noteMenu(sticky) }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var notesList: some View {
        List(results) { sticky in
            NavigationLink(value: sticky.id) {
                MobileStickyRow(sticky: sticky, sessionOnly: library.isSessionOnly(id: sticky.id))
            }
            .contextMenu { noteMenu(sticky) }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { Task { await library.moveToTrash(id: sticky.id) } } label: {
                    Label { Text("Delete", bundle: .module) } icon: { Image(systemName: "trash") }
                }
            }
        }
    }

    @ContentBuilder
    private func noteMenu(_ sticky: Sticky) -> some View {
        ShareLink(item: MobileStickyShareDocument(sticky: sticky), preview: SharePreview(LocalizedStringResource("\(sticky.title)"))) {
            Label { Text("Share", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
        }
        Button(role: .destructive) { Task { await library.moveToTrash(id: sticky.id) } } label: {
            Label { Text("Delete", bundle: .module) } icon: { Image(systemName: "trash") }
        }
    }

    private func createSticky(sessionOnly: Bool = false) {
        guard !creating else { return }
        creating = true
        Task {
            if let sticky = await library.newSticky(sessionOnly: sessionOnly) { library.openSticky(id: sticky.id) }
            creating = false
        }
    }
}
#endif
