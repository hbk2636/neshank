import SwiftUI
import AppKit

extension Notification.Name {
    static let newBookmark = Notification.Name("NeshankYar.newBookmark")
    static let newFolder = Notification.Name("NeshankYar.newFolder")
    static let showChats = Notification.Name("NeshankYar.showChats")
    static let showPalette = Notification.Name("NeshankYar.showPalette")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?
    private var hotKeyObserver: NSObjectProtocol?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // میان‌بر سراسریِ «افزودن سریع» (⌘⇧Space و …)
        HotKeyCenter.shared.start()

        hotKeyObserver = NotificationCenter.default.addObserver(
            forName: .quickAddHotKey,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                QuickAddPanel.shared.show()
            }
        }

        // ⌘V = چسباندن آدرس و افزودن سریع — فقط وقتی فیلد متنی فوکوس نیست
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            self.handleKeyDown(event)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers?.lowercased(),
              chars == "v" || chars == "z"
        else { return event }

        // درون فیلدهای متنی، رفتار عادی سیستم حفظ می‌شود
        guard let first = NSApp.keyWindow?.firstResponder, !(first is NSTextView) else { return event }

        if chars == "v" {
            if let text = NSPasteboard.general.string(forType: .string)?.trimmed,
               URLNormalizer.url(text) != nil {
                QuickAddPanel.shared.show(prefill: text)
                return nil
            }
            return event
        } else {
            if Library.shared.canUndoDelete {
                Library.shared.undoDelete()
                return nil
            }
            return event
        }
    }
}

@main
struct NeshankYarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
        }
        .defaultSize(width: 1400, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L.tr("New Bookmark")) {
                    NotificationCenter.default.post(name: .newBookmark, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(L.tr("Quick Add…")) {
                    QuickAddPanel.shared.show()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button(L.tr("New Folder")) {
                    NotificationCenter.default.post(name: .newFolder, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu(L.tr("Assistant")) {
                Button(L.tr("Command Palette…")) {
                    NotificationCenter.default.post(name: .showPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button(L.tr("Chats…")) {
                    NotificationCenter.default.post(name: .showChats, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                .keyboardShortcut("t", modifiers: [.command, .shift])

            }

            CommandGroup(after: .undoRedo) {
                Button(L.tr("Restore Last Delete")) {
                    Library.shared.undoDelete()
                }
                .disabled(!Library.shared.canUndoDelete)
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(\.layoutDirection, L.direction)
        } label: {
            Image(systemName: "bookmark.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(\.layoutDirection, L.direction)
        }
    }
}
