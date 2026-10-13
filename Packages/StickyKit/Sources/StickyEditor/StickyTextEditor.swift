import Foundation
import StickyDomain
import SwiftUI

/// Native rich text editing shared by iOS and macOS. Text remains plain and
/// editable, with portable bold/italic runs and ordinary list/checklist markers.
public struct StickyTextEditor: View {
    @Binding private var text: String
    @Binding private var richText: StickyRichText?
    @State private var attributedText: AttributedString
    @State private var selection = AttributedTextSelection()
    @FocusState private var isTextFocused: Bool
    @Environment(\.fontResolutionContext) private var fontResolutionContext

    private let startsFocused: Bool

    public init(
        text: Binding<String>,
        richText: Binding<StickyRichText?>,
        startsFocused: Bool = false
    ) {
        _text = text
        _richText = richText
        _attributedText = State(initialValue: StickyRichTextBridge.attributedText(
            text: text.wrappedValue, richText: richText.wrappedValue
        ))
        self.startsFocused = startsFocused
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: editorBinding, selection: $selection)
                .font(.body)
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .focused($isTextFocused)
                .attributedTextFormattingDefinition(
                    StickyFormattingDefinition(context: fontResolutionContext)
                )
                .textInputFormattingControlVisibility(.hidden, for: .all)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(String(localized: "A thought, a list, a little reminder…", bundle: .module))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(String(localized: "Sticky text", bundle: .module))
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        HStack(spacing: 12) {
                            formattingControls
                        }
                        .labelStyle(.iconOnly)
                        Spacer()
                        Button(String(localized: "Done", bundle: .module), systemImage: "keyboard.chevron.compact.down") {
                            isTextFocused = false
                        }
                    }
                }
                #endif

            #if os(macOS)
            HStack(spacing: 4) {
                formattingControls
                Spacer(minLength: 0)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            #endif
        }
        .onAppear {
            if startsFocused { isTextFocused = true }
        }
        .onChange(of: text) { _, _ in synchronizeFromBindings() }
        .onChange(of: richText) { _, _ in synchronizeFromBindings() }
    }

    private var editorBinding: Binding<AttributedString> {
        Binding(get: { attributedText }, set: { newText in
            attributedText = newText
            persistEditor()
        })
    }

    @ViewBuilder
    private var formattingControls: some View {
        Toggle(String(localized: "Bold", bundle: .module), systemImage: "bold", isOn: boldBinding)
            .toggleStyle(.button)
            .keyboardShortcut("b")
            .help(String(localized: "Bold (⌘B)", bundle: .module))

        Toggle(String(localized: "Italic", bundle: .module), systemImage: "italic", isOn: italicBinding)
            .toggleStyle(.button)
            .keyboardShortcut("i")
            .help(String(localized: "Italic (⌘I)", bundle: .module))

        Menu(String(localized: "List", bundle: .module), systemImage: "list.bullet") {
            Button(String(localized: "Bullet List", bundle: .module), systemImage: "list.bullet") {
                editList(.bullet)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Button(String(localized: "Numbered List", bundle: .module), systemImage: "list.number") {
                editList(.numbered)
            }
            Button(String(localized: "Checklist", bundle: .module), systemImage: "checklist") {
                editList(.checklist)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .menuIndicator(.hidden)
        .help(String(localized: "Turn selected lines into a list", bundle: .module))

        Button(String(localized: "Toggle Checkmark", bundle: .module), systemImage: "checkmark.circle") {
            apply(StickyListEditing.toggleCompletion(
                text: String(attributedText.characters),
                richText: currentRichText,
                selection: selectedRange
            ))
        }
        .disabled(!StickyListEditing.containsChecklist(text: text, selection: selectedRange))
        .keyboardShortcut(.return, modifiers: [.command, .shift])
        .help(String(localized: "Check or uncheck selected checklist items", bundle: .module))
    }

    private var boldBinding: Binding<Bool> {
        Binding(get: {
            StickyRichTextBridge.emphasis(
                of: selection.typingAttributes(in: attributedText).font ?? .body,
                in: fontResolutionContext
            ).bold
        }, set: { isBold in
            attributedText.transformAttributes(in: &selection) {
                let style = StickyRichTextBridge.emphasis(
                    of: $0.font ?? .body, in: fontResolutionContext
                )
                $0.font = StickyRichTextBridge.canonicalFont(bold: isBold, italic: style.italic)
            }
            persistEditor()
        })
    }

    private var italicBinding: Binding<Bool> {
        Binding(get: {
            StickyRichTextBridge.emphasis(
                of: selection.typingAttributes(in: attributedText).font ?? .body,
                in: fontResolutionContext
            ).italic
        }, set: { isItalic in
            attributedText.transformAttributes(in: &selection) {
                let style = StickyRichTextBridge.emphasis(
                    of: $0.font ?? .body, in: fontResolutionContext
                )
                $0.font = StickyRichTextBridge.canonicalFont(bold: style.bold, italic: isItalic)
            }
            persistEditor()
        })
    }

    private var currentRichText: StickyRichText? {
        StickyRichTextBridge.richText(from: attributedText, in: fontResolutionContext)
    }

    private var selectedRange: NSRange {
        func offset(_ index: AttributedString.Index) -> Int {
            String(attributedText[..<index].characters).utf16.count
        }
        switch selection.indices(in: attributedText) {
        case let .insertionPoint(index):
            return NSRange(location: offset(index), length: 0)
        case let .ranges(ranges):
            guard let first = ranges.ranges.first, let last = ranges.ranges.last else {
                return NSRange(location: 0, length: 0)
            }
            let lower = offset(first.lowerBound)
            return NSRange(location: lower, length: offset(last.upperBound) - lower)
        }
    }

    private func editList(_ style: StickyListEditing.Style) {
        apply(StickyListEditing.toggle(
            style, text: String(attributedText.characters),
            richText: currentRichText, selection: selectedRange
        ))
    }

    private func apply(_ result: StickyListEditing.Result) {
        attributedText = StickyRichTextBridge.attributedText(text: result.text, richText: result.richText)
        if let range = Range(result.selection, in: result.text),
           let lower = AttributedString.Index(range.lowerBound, within: attributedText),
           let upper = AttributedString.Index(range.upperBound, within: attributedText) {
            selection = result.selection.length == 0
                ? AttributedTextSelection(insertionPoint: lower)
                : AttributedTextSelection(range: lower..<upper)
        } else {
            selection = AttributedTextSelection(insertionPoint: attributedText.endIndex)
        }
        persistEditor()
        isTextFocused = true
    }

    private func persistEditor() {
        let plain = String(attributedText.characters)
        let formatting = currentRichText
        // Model text setters may invalidate stale formatting. Publish text
        // first, then the emphasis calculated for precisely that text.
        if text != plain { text = plain }
        if richText != formatting { richText = formatting }
    }

    private func synchronizeFromBindings() {
        let plain = String(attributedText.characters)
        guard text != plain || richText != currentRichText else { return }
        attributedText = StickyRichTextBridge.attributedText(text: text, richText: richText)
        selection = AttributedTextSelection(insertionPoint: attributedText.endIndex)
    }
}

