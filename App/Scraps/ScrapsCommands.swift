import AppIntents
import OSLog
import StickyDomain
import StickyEditor
import StickyIntents
import StickyStorage
import StickyUI
import SwiftUI

struct ScrapsCommands: Commands {
    private var board: StickyBoard { .shared }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…", action: board.showSettings).keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("New Sticky") { board.newSticky() }.keyboardShortcut("n")
            Button("New Sticky (This Session Only)") { board.newSticky(sessionOnly: true) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Sticky in Color…", action: board.newStickyInColor)
            Divider()
            Button("Recently Deleted…") { ScrapsUtilityWindows.shared.showRecentlyDeleted() }
        }
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .windowSize) {
            Button(board.activeModel?.isCollapsed == true ? String(localized: "Expand Sticky") : String(localized: "Collapse Sticky"), action: board.toggleActiveCollapse)
                .keyboardShortcut("m").disabled(board.activeModel == nil)
        }
        CommandGroup(before: .windowArrangement) {
            Button("Show All Stickies", action: board.showAll)
        }
        CommandMenu("Sticky") {
            Group {
                Button("Float on Top", action: board.toggleActiveFloating)
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Show on All Desktops", action: board.toggleActiveAllSpaces)
                Menu("Color") {
                    ForEach(StickyColor.allCases, id: \.self) { color in
                        Button(color.localizedName) { board.setActiveColor(color) }
                    }
                }
                Divider()
                Button("Send to Notes", action: board.sendActiveToNotes).disabled(board.activeModel?.canSend != true)
                Button("Copy Text", action: board.copyActiveText).disabled(board.activeModel?.text.isEmpty != false)
            }
            .disabled(board.activeModel == nil)
            Divider()
            Button("Close All Stickies", action: board.closeAll)
                .disabled(!board.hasOpenStickies)
                .keyboardShortcut("w", modifiers: [.command, .option])
        }
        TextEditingCommands()
    }
}
