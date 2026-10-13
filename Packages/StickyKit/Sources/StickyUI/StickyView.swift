import SwiftUI

/// The inside of one sticky: plain text, and one slim row of icon buttons.
///
/// No colour of its own. The glass is the panel's (see
/// `StickyGlassHostingView`), symbols are monochrome and every colour is a
/// system one, so a sticky reads as part of the system rather than as a
/// lookalike of Apple's Stickies.
struct StickyView: View {
    @Bindable var model: StickyModel
    @FocusState private var isTextFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $model.text)
                .scrollContentBackground(.hidden)
                .focused($isTextFocused)
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Type here. Send it to Notes to keep it.")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .accessibilityLabel("Sticky text")

            if let status = model.status {
                StickyStatusLine(status: status)
            }

            controls
        }
        .onAppear {
            if model.startsFocused { isTextFocused = true }
        }
        .confirmationDialog(
            "Delete this sticky?",
            isPresented: $model.isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { model.confirmDelete() }
            Button("Send to Notes", action: model.sendToNotes)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its text will be lost. Send it to Notes first to keep it.")
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button("Close", systemImage: "xmark") { model.requestClose() }
                .keyboardShortcut("w")
                .help("Close this sticky")

            Button("Send to Notes", systemImage: "square.and.arrow.up", action: model.sendToNotes)
                .disabled(!model.canSend)
                .help(model.sendUnavailableReason ?? "Send this sticky to Notes")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    model.sendButtonFrame = $0
                }

            Spacer(minLength: 0)

            Menu("More", systemImage: "ellipsis.circle") {
                Button("Copy Text", systemImage: "doc.on.doc", action: model.copyText)
                    .disabled(model.text.isEmpty)
                Toggle("Float on Top", systemImage: "pin", isOn: $model.floatsOnTop)
            }
            .menuIndicator(.hidden)
            .help("Copy the text or choose whether this sticky floats on top")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // The row is the one place a sticky can be grabbed without selecting
        // text, so it drags the window.
        .stickyWindowDrag()
    }
}
