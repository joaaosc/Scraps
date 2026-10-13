#if os(iOS)
import StickyDomain
import StickyEditor
import SwiftUI

struct MobileNewColorView: View {
    @Bindable var library: MobileStickyLibrary
    @State private var selection: StickyColor
    @State private var creating = false
    @Environment(\.dismiss) private var dismiss

    init(library: MobileStickyLibrary) {
        self.library = library
        _selection = State(initialValue: StickyColor(rawValue: UserDefaults.standard.string(forKey: "defaultStickyColor") ?? "clear") ?? .clear)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StickyColorPalette(selection: $selection)
                } header: {
                    Text("Sticky Color", bundle: .module)
                }
            }
            .navigationTitle(Text("New Sticky in Color…", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                        .disabled(creating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !creating else { return }
                        creating = true
                        Task {
                            if let sticky = await library.newSticky(color: selection) {
                                library.navigation.append(sticky.id)
                                dismiss()
                            }
                            creating = false
                        }
                    } label: {
                        Text("Create", bundle: .module)
                    }
                    .disabled(creating)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
