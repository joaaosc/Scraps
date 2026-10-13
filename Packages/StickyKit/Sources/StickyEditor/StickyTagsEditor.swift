import StickyDomain
import SwiftUI

public struct StickyTagsEditor: View {
    @Binding private var tags: [String]
    @State private var value: String
    @Environment(\.dismiss) private var dismiss
    public init(tags: Binding<[String]>) {
        _tags = tags
        _value = State(initialValue: tags.wrappedValue.joined(separator: ", "))
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags", bundle: .module).font(.headline)
            TextField(String(localized: "Work, Ideas, Personal", bundle: .module), text: $value)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Text("Separate tags with commas.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                Spacer()
                Button(String(localized: "Save", bundle: .module), action: save)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding().frame(minWidth: 280)
    }
    private func save() {
        tags = Sticky.normalizedTags(value.components(separatedBy: ","))
        dismiss()
    }
}
