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

        // هارنس آزمایشی (فقط debug): با متغیر محیطی NESHANK_SHOT از پنجره عکس می‌گیرد و خارج می‌شود
        #if DEBUG
        if let shotPath = ProcessInfo.processInfo.environment["NESHANK_SHOT"], !shotPath.isEmpty {
            let openSettings = ProcessInfo.processInfo.environment["NESHANK_OPEN_SETTINGS"] == "1"
            let selectFirst = ProcessInfo.processInfo.environment["NESHANK_SELECT_FIRST"] == "1"
            let openChats = ProcessInfo.processInfo.environment["NESHANK_OPEN_CHATS"] == "1"
            let openYtdlp = ProcessInfo.processInfo.environment["NESHANK_OPEN_YTDLP"] == "1"
            let openMindmap = ProcessInfo.processInfo.environment["NESHANK_OPEN_MINDMAP"] == "1"
            // تولید خودکار نقشه برای دادهٔ آغازین: NESHANK_MINDMAP_AUTO=<url>
            let mindmapAutoURL = ProcessInfo.processInfo.environment["NESHANK_MINDMAP_AUTO"] ?? ""
            // اندازهٔ آزمایشی پنجره، مثلاً NESHANK_WINDOW=1000x640
            if let size = ProcessInfo.processInfo.environment["NESHANK_WINDOW"] {
                let parts = size.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        NSApp.windows.first { $0.isVisible }?
                            .setContentSize(NSSize(width: parts[0], height: parts[1]))
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (openSettings ? 1.5 : 2.0)) {
                if openSettings {
                    AppActions.openSettings()
                } else if selectFirst {
                    Library.shared.selectedId = Library.shared.results.first?.id
                } else if openChats {
                    NotificationCenter.default.post(name: .showChats, object: nil)
                } else if !mindmapAutoURL.isEmpty {
                    // URL داده می‌شود، پنجرهٔ ابزار باز و پایپ‌لاین تولید خودکار روشن می‌شود
                    MindMapToolWindow.shared.show(url: mindmapAutoURL, title: "Seed")
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        MindMapToolWindow.shared.model.start()
                        print("MMAUTO: generation started → \(mindmapAutoURL)")
                        // گزارش وضعیت تا پایان (موفق یا خطا) — برای دیباگ بدون نگاه به پنجره
                        for _ in 0..<160 {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            let m = MindMapToolWindow.shared.model
                            print("MMAUTO: phase=\(m.phase) status=\(m.statusText)")
                            if let t = m.errorTitle { print("MMAUTO-ERR: \(t) | \(m.errorDetail ?? "-")") }
                            if m.phase == .result || m.phase == .failed { break }
                        }
                    }
                } else if openMindmap {
                    // نقشهٔ ذخیره‌شدهٔ واقعی کاربر (اگر باشد) — برای بازبینی پنل
                    // mindMaps با تاخیر بار می‌شود → تا ۶ ثانیه صبر
                    Task { @MainActor in
                        // mindMaps فقط در scope نقشه‌ها بارگذاری می‌شود → موقتاً سوییچ و برگشت
                        Library.shared.scope = .mindMaps
                        if Library.shared.mindMaps.isEmpty {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            Library.shared.reload()
                        }
                        if let record = Library.shared.mindMaps.first {
                            MindMapToolWindow.shared.show(record: record)
                        } else {
                            MindMapToolWindow.shared.show(url: "https://example.com", title: "Harness")
                        }
                        Library.shared.scope = .all
                    }
                    // بازتولید کرش تعویض تب: NESHANK_MINDMAP_TABS=1 → تزریق نقشه و چرخهٔ تب‌ها
                    if ProcessInfo.processInfo.environment["NESHANK_MINDMAP_TABS"] == "1" {
                        Task { @MainActor in
                            let m = MindMapToolWindow.shared.model
                            m.mapJSON = """
                            {"meta":{"title":"Harness","sourceUrl":"","createdAt":"2026-10-01T00:00:00Z","model":"t","language":"en","direction":1,"theme":"dark","layout":"tree"},"root":{"id":"root","text":"Topic","children":[{"id":"b1","text":"Branch One","children":[{"id":"n1","text":"Leaf A","children":[]},{"id":"n2","text":"Leaf B","children":[]}]},{"id":"b2","text":"Branch Two","children":[{"id":"n3","text":"Leaf C","children":[]}]},{"id":"b3","text":"Branch Three","children":[{"id":"n4","text":"Leaf D","children":[]},{"id":"n5","text":"Leaf E","children":[]},{"id":"n6","text":"Leaf F","children":[]}]}]}}
                            """
                            m.pageTitle = "Harness"
                            m.phase = .result
                            m.tab = .map
                            print("MMTAB: injected, waiting for render")
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            guard ProcessInfo.processInfo.environment["NESHANK_MINDMAP_CYCLE"] == "1" else { return }
                            for t in [MindMapToolModel.Tab.tree, .markdown, .json, .map, .tree, .map] {
                                print("MMTAB: -> \(t.rawValue)")
                                m.tab = t
                                let b = MindMapToolWindow.shared.bridge
                                for k in 1...6 {
                                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                                    print("MMTAB:   +\(k)s loaded=\(b.loaded) nodes=\(b.nodeCount) err=\(b.renderError ?? "-")")
                                }
                            }
                            print("MMTAB: cycle done")
                        }
                    }
                } else if openYtdlp {
                    VideoDownloadToolWindow.shared.show(bookmark: nil)
                    // تست خودکار: NESHANK_YTDLP_AUTO=<url> → دانلود صوتی واقعی
                    if let autoURL = ProcessInfo.processInfo.environment["NESHANK_YTDLP_AUTO"], !autoURL.isEmpty {
                        VideoDownloadToolWindow.shared.model.urlText = autoURL
                        VideoDownloadToolWindow.shared.model.mode = .audio
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            VideoDownloadToolWindow.shared.model.start()
                        }
                    }
                }
            }
            let captureDelay = Double(ProcessInfo.processInfo.environment["NESHANK_SHOT_DELAY"] ?? "") ?? 4.5
            DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) {
                print("WINDBG: " + NSApp.windows.map {
                    "\($0.title)|key=\($0.isKeyWindow)|vis=\($0.isVisible)|n=\($0.contentView != nil)"
                }.joined(separator: " ;; "))
                if let win = (openYtdlp
                                  ? NSApp.windows.first { $0.title.contains("ویدیو") || $0.title.contains("Video") }
                                  : (openMindmap || !mindmapAutoURL.isEmpty
                                  ? NSApp.windows.first { $0.title.contains("طراحی") || $0.title.contains("Mind Map") }
                                  : (openSettings
                                      ? (NSApp.keyWindow ?? NSApp.windows.reversed().first { $0.isVisible })
                                      : (NSApp.keyWindow ?? NSApp.windows.first(where: { !$0.title.isEmpty }))))) {
                    let image = CGWindowListCreateImage(
                        .null,
                        .optionIncludingWindow,
                        CGWindowID(win.windowNumber),
                        [.bestResolution, .boundsIgnoreFraming]
                    )
                    print("SHOTDBG: image nil?\(image == nil) win=\(win.title)")
                    if let image = image {
                        let rep = NSBitmapImageRep(cgImage: image)
                        if let data = rep.representation(using: .png, properties: [:]) {
                            let out = URL(fileURLWithPath: shotPath)
                            try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                                                     withIntermediateDirectories: true)
                            do {
                                try data.write(to: out)
                                print("SHOTDBG: saved \(shotPath)")
                            } catch {
                                print("SHOTDBG: write failed: \(error)")
                            }
                        } else {
                            print("SHOTDBG: png data nil")
                        }
                    }
                }
                NSApp.terminate(nil)
            }
        }
        #endif
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
