import AppKit
import Carbon
import Testing
@testable import Drift

@MainActor @Test func shortcutsKeepModifiersLabelsAndPersistAcrossLaunches() throws {
    _ = NSApplication.shared
    let suite = "MonkeytypeQuick.ShortcutTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(KeyboardShortcut.load(from: defaults).display == "⌥+Space")
    func event(_ flags: NSEvent.ModifierFlags, keyCode: Int, characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                     windowNumber: 0, context: nil, characters: characters,
                                     charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode)))
    }
    let modified = try #require(KeyboardShortcut(event: event([.command, .shift], keyCode: kVK_ANSI_J, characters: "J")))
    #expect(modified.keyCode == UInt32(kVK_ANSI_J))
    #expect(modified.modifiers == UInt32(cmdKey | shiftKey))
    #expect(modified.display == "⇧+⌘+J")
    modified.save(to: defaults)
    let reopened = try #require(UserDefaults(suiteName: suite))
    #expect(KeyboardShortcut.load(from: reopened) == modified)
    #expect(KeyboardShortcut(event: try event([], keyCode: kVK_ANSI_J, characters: "j")) == nil)
    #expect(KeyboardShortcut(event: try event([.shift], keyCode: kVK_ANSI_J, characters: "J")) == nil)
    let optionSpace = try #require(KeyboardShortcut(event: event([.option], keyCode: kVK_Space, characters: " ")))
    #expect(optionSpace == .standard)
    optionSpace.save(to: defaults)
    #expect(KeyboardShortcut.load(from: reopened).display == "⌥+Space")
}
