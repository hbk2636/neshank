import SwiftUI
import AppKit

// MARK: - پالت فرمان (⌘K)

/// همه‌چیز از یک کادر: دستورها، پرش به محدوده‌ها، جستجوی نشانک‌ها و پرسش از دستیار/کتابخانه.
struct CommandPalette: View {
    @Binding var isPresented: Bool

    @ObservedObject private var lib = Library.shared
    @ObservedObject private var chats = ChatStore.shared

    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool
    @State private var keyMonitor: Any?

    struct Item: Identifiable {
        enum Kind { case command, bookmark, ask, chat }
        var id: String
        var kind: Kind
        var title: String
        var subtitle: String = ""
        var icon: String = "command"
        var favicon: String?
        var bookmarkId: Int64?
        var run: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L.tr("Command, bookmark or question…"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onSubmit { runSelected() }
                    .onChange(of: query) { _ in index = 0 }
                if !query.isBlank {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Text("⌘K")
                    .font(.system(size: 10))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.secondary)
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L.tr("Close (Esc)"))
            }
            .padding(.horizontal, 14)
            .frame(height: 46)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if items.isEmpty {
                        Text(L.tr("Nothing found"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        row(item, selected: i == index)
                            .onTapGesture {
                                index = i
                                runSelected()
                            }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 380)

            Divider()
            HStack(spacing: 10) {
                hint("↑↓", L.tr("Navigate"))
                hint("↩", L.tr("Run"))
                hint("esc", L.tr("Close"))
                Spacer()
                Text(L.tf("%@ bookmarks in this scope", Digits.fa(lib.results.count)))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
        }
        .frame(width: 620)
        .background(.regularMaterial)
        .opaquePanelBacking()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 26, y: 10)
        .environment(\.layoutDirection, L.direction)
        .onAppear {
            focused = true
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: isPresented) { _ in focused = isPresented }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
            Text(label).font(.system(size: 10))
        }
        .foregroundStyle(.secondary)
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 9) {
            if let favicon = item.favicon {
                FaviconView(path: favicon, size: 16)
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(selected ? Color.white : Color.secondary)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                if !item.subtitle.isBlank {
                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .opacity(selected ? 0.85 : 0.6)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if item.kind == .ask {
                Text(L.tr("Ask"))
                    .font(.system(size: 9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(selected ? 0.2 : 0.08)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? (AppTheme.accent ?? .accentColor).opacity(0.9) : Color.clear)
        )
        .foregroundStyle(selected ? Color.white : Color.primary)
        .contentShape(Rectangle())
    }

    // MARK: اقلام

    private var items: [Item] {
        var out: [Item] = []
        let q = query.trimmed

        if q.isEmpty {
            out += commandItems
        } else {
            // دستورهای منطبق
            out += commandItems.filter {
                $0.title.localizedCaseInsensitiveContains(q) || $0.subtitle.localizedCaseInsensitiveContains(q)
            }
            // نشانک‌های منطبق
            for b in lib.contextBookmarks(for: q, limit: 6) {
                out.append(Item(id: "b-\(b.id)",
                                kind: .bookmark,
                                title: b.displayTitle,
                                subtitle: b.domain,
                                favicon: b.favicon,
                                bookmarkId: b.id,
                                run: { self.select(b.id) }))
            }
            // گفتگوهای منطبق
            for chat in chats.chats.filter({ $0.title.localizedCaseInsensitiveContains(q) }).prefix(4) {
                out.append(Item(id: "c-\(chat.id)",
                                kind: .chat,
                                title: chat.title.isBlank ? L.tr("New Library Chat") : chat.title,
                                subtitle: L.tf("Chat · %@ messages", Digits.fa(chat.messageCount)),
                                icon: chat.kind.icon,
                                run: {
                                    chats.select(chat.id)
                                    NotificationCenter.default.post(name: .showChats, object: nil)
                                }))
            }
            // پرسش‌ها
            out.append(Item(id: "ask-library",
                            kind: .ask,
                            title: L.tf("Ask the library: “%@”", q),
                            subtitle: L.tr("Answer with references to your bookmarks"),
                            icon: "books.vertical",
                            run: { self.askLibrary(q) }))
            out.append(Item(id: "ask-assistant",
                            kind: .ask,
                            title: L.tf("Ask about the selected bookmark: “%@”", q),
                            subtitle: lib.selectedId.flatMap { lib.bookmark(id: $0) }?.displayTitle ?? L.tr("No bookmark selected"),
                            icon: "sparkles",
                            run: { self.askSelectedBookmark(q) }))
        }
        return out
    }

    private var commandItems: [Item] {
        var out: [Item] = [
            Item(id: "new", kind: .command, title: L.tr("New Bookmark"), subtitle: "⌘N", icon: "plus",
                 run: { self.close(); self.lib.editing = .new(folderId: nil) }),
            Item(id: "quick", kind: .command, title: L.tr("Quick Add in any app"), subtitle: "⌘⇧Space", icon: "bolt",
                 run: { self.close(); QuickAddPanel.shared.show() }),
            Item(id: "chats", kind: .command, title: L.tr("Chats"), subtitle: L.tr("All previous chats"), icon: "bubble.left.and.bubble.right",
                 run: { self.close(); NotificationCenter.default.post(name: .showChats, object: nil) }),
            Item(id: "ask", kind: .command, title: L.tr("Ask the whole library"), subtitle: L.tr("New Library Chat"), icon: "books.vertical",
                 run: { self.close(); self.newLibraryChat() }),
            Item(id: "mindmap", kind: .command, title: L.tr("Mind Map Designer"), subtitle: L.tr("Separate window: design a mind map"), icon: "brain.head.profile",
                 run: { self.close(); ShellTools.openMindMap() }),
            Item(id: "ytdlp", kind: .command, title: L.tr("Video Downloader"), subtitle: L.tr("Separate window: download a video"), icon: "arrow.down.circle",
                 run: { self.close(); ShellTools.openVideoDownload() }),
        ]

        if let id = lib.selectedId, let b = lib.bookmark(id: id) {
            out.insert(Item(id: "chat-bookmark", kind: .command,
                            title: L.tf("Chat about “%@”", b.displayTitle),
                            subtitle: b.domain, icon: "sparkles", favicon: b.favicon,
                            run: { self.close(); self.openBookmarkChat(id) }), at: 3)
        }

        // پرش به محدوده‌ها
        out.append(Item(id: "scope-all", kind: .command, title: L.tr("All Bookmarks"), icon: "tray.full",
                        run: { self.close(); self.lib.scope = .all }))
        out.append(Item(id: "scope-starred", kind: .command, title: L.tr("Starred"), icon: "star",
                        run: { self.close(); self.lib.scope = .starred }))
        out.append(Item(id: "scope-trash", kind: .command, title: L.tr("Trash"), icon: "trash",
                        run: { self.close(); self.lib.scope = .trash }))
        for folder in lib.folders.prefix(8) {
            out.append(Item(id: "folder-\(folder.id)", kind: .command, title: folder.name,
                            subtitle: L.tr("Folder"), icon: "folder",
                            run: { self.close(); self.lib.scope = .folder(folder.id) }))
        }
        for tag in lib.tags.prefix(6) {
            out.append(Item(id: "tag-\(tag.name)", kind: .command, title: tag.name,
                            subtitle: L.tf("Tag · %@", Digits.fa(tag.count)),
                            icon: "tag",
                            run: { self.close(); self.lib.scope = .tag(tag.name) }))
        }
        out.append(Item(id: "settings", kind: .command, title: L.tr("Settings"), subtitle: L.tr("Assistant, appearance, data"), icon: "gearshape",
                        run: { self.close(); AppActions.openSettings() }))
        return out
    }

    // MARK: اجرا

    /// ناوبری صفحه‌کلید پالت (↑↓/Esc) — راهنمای پایین کادر واقعی می‌شود، نه تزئینی
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: // Esc
                isPresented = false
                return nil
            case 125: // ↓
                let count = items.count
                if count > 0 { index = min(index + 1, count - 1) }
                return nil
            case 126: // ↑
                index = max(index - 1, 0)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func runSelected() {
        guard items.indices.contains(index) else { return }
        items[index].run()
    }

    private func close() {
        isPresented = false
    }

    private func select(_ bookmarkId: Int64) {
        lib.selectedId = bookmarkId
        close()
    }

    private func openBookmarkChat(_ bookmarkId: Int64) {
        guard let b = lib.bookmark(id: bookmarkId) else { return }
        chats.ensureChat(forBookmark: bookmarkId, title: b.displayTitle)
        NotificationCenter.default.post(name: .showChats, object: nil)
    }

    private func newLibraryChat() {
        chats.create(kind: .library, bookmarkId: nil, title: L.tr("Ask the Library"))
        NotificationCenter.default.post(name: .showChats, object: nil)
    }

    private func askLibrary(_ question: String) {
        let items = lib.contextBookmarks(for: question, limit: 8)
            .map { AIAdvisor.ContextItem(bookmark: $0, excerpt: lib.savedContent(id: $0.id)) }
        let system = AIAdvisor.librarySystemPrompt(profile: AIConfig.load().profile)
            + "\n\n" + AIAdvisor.libraryUserPrompt(question: question, items: items)

        guard let chatId = chats.selectedId, chats.chat(chatId)?.kind == .library else {
            let id = chats.create(kind: .library, bookmarkId: nil, title: ChatText.autoTitle(question))
            ask(chatId: id, question: question, system: system, citations: AIAdvisor.citations(items))
            NotificationCenter.default.post(name: .showChats, object: nil)
            close()
            return
        }
        ask(chatId: chatId, question: question, system: system, citations: AIAdvisor.citations(items))
        NotificationCenter.default.post(name: .showChats, object: nil)
        close()
    }

    private func askSelectedBookmark(_ question: String) {
        guard let id = lib.selectedId, let b = lib.bookmark(id: id) else { return }
        let chatId = chats.ensureChat(forBookmark: id, title: b.displayTitle)
        let system = AIClient.systemPrompt(profile: AIConfig.load().profile,
                                           bookmark: b,
                                           pageContent: lib.savedContent(id: id))
        ask(chatId: chatId, question: question, system: system, citations: [])
        NotificationCenter.default.post(name: .showChats, object: nil)
        close()
    }

    private func ask(chatId: Int64, question: String, system: String, citations: [ChatMessage.Citation]) {
        Task {
            await chats.ask(chatId: chatId, question: question, systemPrompt: system, citations: citations)
        }
    }
}
