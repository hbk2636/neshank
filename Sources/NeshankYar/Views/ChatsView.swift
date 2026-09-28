import SwiftUI
import AppKit

// MARK: - صفحهٔ گفتگوها

/// همهٔ گفتگوهای انجام‌شده: ادامه بده، تغییر نام بده، پیام‌ها را پاک کن («شروع از نو»)
/// یا کل گفتگو را حذف کن. هر گفتگو یا دربارهٔ یک نشانک است یا «پرسش از کل کتابخانه».
struct ChatsView: View {
    @ObservedObject private var store = ChatStore.shared
    @ObservedObject private var lib = Library.shared
    /// بستن صفحه (از بیرون تزریق می‌شود تا به‌جای شیت، لایهٔ درون‌پنجره باشد)
    var onClose: () -> Void = {}

    @State private var input = ""
    @State private var renaming: Int64?
    @State private var renameText = ""
    @State private var confirmDelete: Int64?
    @State private var confirmClear: Int64?
    @State private var confirmDeleteAll = false
    @State private var showNewMenu = false

    var body: some View {
        HStack(spacing: 0) {
            listColumn
            Divider()
            conversationColumn
        }
        .frame(minWidth: 960, idealWidth: 1120, minHeight: 620, idealHeight: 720)
        .environment(\.layoutDirection, L.direction)
        .environment(\.locale, Locale(identifier: "fa_IR"))
        .onAppear { store.reloadChats() }
        .confirmationDialog(L.tr("Delete this chat and all its messages?"),
                            isPresented: Binding(get: { confirmDelete != nil },
                                                 set: { if !$0 { confirmDelete = nil } })) {
            Button(L.tr("Delete Chat"), role: .destructive) {
                if let id = confirmDelete { store.delete(id) }
                confirmDelete = nil
            }
        }
        .confirmationDialog(L.tr("Clear all messages in this chat? (The chat is kept)"),
                            isPresented: Binding(get: { confirmClear != nil },
                                                 set: { if !$0 { confirmClear = nil } })) {
            Button(L.tr("Start Fresh"), role: .destructive) {
                if let id = confirmClear { store.clearMessages(id) }
                confirmClear = nil
            }
        }
        .confirmationDialog(L.tr("Delete all chats?"),
                            isPresented: $confirmDeleteAll) {
            Button(L.tr("Delete All"), role: .destructive) { store.deleteAll() }
        }
    }

    // MARK: ستون فهرست گفتگوها

    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L.tr("Chats"))
                    .font(.headline)
                Text(Digits.fa(store.chats.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button {
                        newLibraryChat()
                    } label: {
                        Label(L.tr("Ask the whole library"), systemImage: "books.vertical")
                    }
                    Button {
                        newBookmarkChat()
                    } label: {
                        Label(lib.selectedId.flatMap { lib.bookmark(id: $0) }?.displayTitle ?? L.tr("About Selected Bookmark"),
                              systemImage: "bookmark")
                    }
                    .disabled(lib.selectedId == nil)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help(L.tr("New Library Chat"))
            }
            .padding(.horizontal, 12)
            .frame(height: 42)

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField(L.tr("Search chats…"), text: $store.search)
                    .textFieldStyle(.plain)
                if !store.search.isBlank {
                    Button {
                        store.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            if store.chats.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(store.search.isBlank ? L.tr("No chats yet") : L.tr("No chats found"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(get: { store.selectedId },
                                        set: { store.select($0) })) {
                    ForEach(store.chats) { chat in
                        chatRow(chat).tag(chat.id)
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack(spacing: 8) {
                Button {
                    confirmDeleteAll = true
                } label: {
                    Label(L.tr("Delete All"), systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(store.chats.isEmpty)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Text(L.tr("Close")).font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
        }
        .frame(width: 296)
    }

    private func chatRow(_ chat: Chat) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 5) {
                if chat.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange)
                }
                Text(chat.title.isBlank || chat.title == "گفتگوی تازه" ? L.tr("New Library Chat") : chat.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Self.relative(chat.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 5) {
                Image(systemName: chat.kind.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(chat.kind == .bookmark ? (chat.bookmarkTitle ?? L.tr("Bookmark")) : L.tr("Ask the Library"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if chat.messageCount > 0 {
                    Text(L.tf("%@ messages", Digits.fa(chat.messageCount)))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            if !chat.preview.isBlank {
                Text(chat.preview)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(L.tr("Continue")) { store.select(chat.id) }
            Button(L.tr("Rename…")) {
                renaming = chat.id
                renameText = chat.title
            }
            Button(chat.pinned ? L.tr("Unpin") : L.tr("Pin")) {
                store.setPinned(chat.id, !chat.pinned)
            }
            Divider()
            Button(L.tr("Start Fresh (Clear Messages)")) { confirmClear = chat.id }
            Button(L.tr("Delete Chat"), role: .destructive) { confirmDelete = chat.id }
        }
        .popover(isPresented: Binding(get: { renaming == chat.id },
                                      set: { if !$0 { renaming = nil } })) {
            VStack(alignment: .trailing, spacing: 8) {
                Text(L.tr("Chat Name")).font(.caption).foregroundStyle(.secondary)
                TextField("", text: $renameText)
                    .frame(width: 220)
                    .onSubmit {
                        store.rename(chat.id, title: renameText)
                        renaming = nil
                    }
                HStack {
                    Button(L.tr("Save")) {
                        store.rename(chat.id, title: renameText)
                        renaming = nil
                    }
                    Button(L.tr("Cancel")) { renaming = nil }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(12)
        }
    }

    // MARK: ستون گفتگو

    private var conversationColumn: some View {
        VStack(spacing: 0) {
            conversationHeader
            Divider()
            messagesArea
            Divider()
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chat: Chat? { store.selectedId.flatMap { store.chat($0) } }

    private var conversationHeader: some View {
        HStack(spacing: 8) {
            if let chat {
                Image(systemName: chat.kind.icon)
                    .foregroundStyle(AppTheme.accent ?? .accentColor)
                Text(chat.title.isBlank || chat.title == "گفتگوی تازه" ? L.tr("New Library Chat") : chat.title)
                    .font(.headline)
                    .lineLimit(1)
                if let bm = chat.bookmarkId, let b = lib.bookmark(id: bm) {
                    Button {
                        lib.selectedId = bm
                    } label: {
                        HStack(spacing: 4) {
                            FaviconView(path: b.favicon, size: 13)
                            Text(b.displayTitle).font(.caption).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(L.tr("Show this bookmark in the main window"))
                }
            } else {
                Text(L.tr("No Chat Selected"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if store.busy {
                ProgressView().controlSize(.small)
            }

            Spacer()

            if let chat {
                Button {
                    store.setPinned(chat.id, !chat.pinned)
                } label: {
                    Image(systemName: chat.pinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.borderless)
                .help(chat.pinned ? L.tr("Unpin") : L.tr("Pin"))

                Button {
                    confirmClear = chat.id
                } label: {
                    Image(systemName: "eraser")
                }
                .buttonStyle(.borderless)
                .help(L.tr("Start Fresh"))

                Button {
                    confirmDelete = chat.id
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L.tr("Delete Chat"))
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L.tr("Close (Esc)"))
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(.bar)
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.messages.isEmpty { emptyHint }

                    ForEach(store.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if store.busy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L.tr("Assistant is typing…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .id("busy")
                        .padding(.horizontal, 4)
                    }

                    if let error = store.errorText {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .onChange(of: store.messages.count) { _ in
                withAnimation { proxy.scrollTo(store.messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: store.busy) { _ in
                withAnimation { proxy.scrollTo("busy", anchor: .bottom) }
            }
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let chat, chat.kind == .library {
                Text(L.tr("Ask the Entire Library"))
                    .font(.callout.weight(.semibold))
                Text(L.tr("For example: “What have I saved about resin safety?” — answers cite the matching bookmarks."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                librarySuggestions
            } else if let chat, let bm = chat.bookmarkId, let b = lib.bookmark(id: bm) {
                Text(b.displayTitle)
                    .font(.callout.weight(.semibold))
                Text(L.tr("Tap a quick question or type your own; the chat is saved and you can continue it anytime."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                quickActions
            } else {
                Text(L.tr("Select a chat from the list or start a new one."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 24)
    }

    private var librarySuggestions: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach([L.tr("What do I have on safety and ventilation?"),
                     L.tr("Which bookmarks should I revisit before buying?"),
                     L.tr("What topic have I saved the most?")], id: \.self) { text in
                Button {
                    input = text
                    send()
                } label: {
                    Label(text, systemImage: "sparkle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 6)], spacing: 6) {
            ForEach(AIClient.QuickAction.all) { action in
                Button {
                    input = action.prompt
                    send()
                } label: {
                    Label(action.title, systemImage: action.icon)
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if !isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Text(message.content)
                    .textSelection(.enabled)
                    .font(.callout)
                    .multilineTextAlignment(.leading)

                if !message.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.tr("Sources"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        FlowRow(spacing: 5) {
                            ForEach(message.citations) { cite in
                                Button {
                                    lib.selectedId = cite.bookmarkId
                                } label: {
                                    Label(cite.title, systemImage: "bookmark")
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill((AppTheme.accent ?? .accentColor).opacity(0.14)))
                                }
                                .buttonStyle(.plain)
                                .help(L.tf("Show “%@” in the main window", cite.title))
                            }
                        }
                    }
                }

                Text(Self.time(message.createdAt))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isUser ? (AppTheme.accent ?? .accentColor).opacity(0.16)
                                 : Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .frame(maxWidth: 640, alignment: isUser ? .trailing : .leading)

            if isUser { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let chat {
                HStack(spacing: 8) {
                    TextField(chat.kind == .library
                              ? L.tr("Ask your library… (e.g. what do I have about resin?)")
                              : L.tr("Type your question…"),
                              text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send() }

                    Button {
                        send()
                    } label: {
                        if store.busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(L.tr("Send"), systemImage: "arrow.up.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.busy || input.trimmed.isEmpty)
                }

                Text(chat.kind == .library
                     ? L.tr("Answers are based on your own bookmarks, with sources listed below the reply.")
                     : L.tr("This chat is saved; continue it later from this page."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text(L.tr("To get started, create a new chat."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: کنش‌ها

    private func newLibraryChat() {
        store.create(kind: .library, bookmarkId: nil, title: L.tr("Ask the Library"))
    }

    private func newBookmarkChat() {
        guard let id = lib.selectedId, let b = lib.bookmark(id: id) else { return }
        store.ensureChat(forBookmark: id, title: b.displayTitle)
    }

    private func send() {
        let text = input.trimmed
        guard !text.isEmpty, !store.busy else { return }

        if store.selectedId == nil {
            newLibraryChat()
        }
        guard let chatId = store.selectedId else { return }
        input = ""
        store.errorText = nil

        let cfg = AIConfig.load()
        var system = ""
        var citations: [ChatMessage.Citation] = []

        if let chat = store.chat(chatId), chat.kind == .bookmark, let bm = chat.bookmarkId,
           let b = lib.bookmark(id: bm) {
            system = AIClient.systemPrompt(profile: cfg.profile,
                                           bookmark: b,
                                           pageContent: lib.savedContent(id: bm))
        } else {
            let items = lib.contextBookmarks(for: text, limit: 8)
                .map { AIAdvisor.ContextItem(bookmark: $0, excerpt: lib.savedContent(id: $0.id)) }
            citations = AIAdvisor.citations(items)
            system = AIAdvisor.librarySystemPrompt(profile: cfg.profile)
                + "\n\n" + AIAdvisor.libraryUserPrompt(question: text, items: items)
        }

        Task {
            await store.ask(chatId: chatId,
                            question: text,
                            systemPrompt: system,
                            citations: citations)
        }
    }

    // MARK: قالب‌بندی

    static func relative(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return time(date)
        }
        if cal.isDateInYesterday(date) { return L.tr("Yesterday") }
        return Dates.persian(date)
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fa_IR")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - چیدمان جریانی (برای تراشه‌های منابع)

/// ردیف‌های افقی که سرِ ردیف می‌شکنند (FlowLayout سادهٔ سبک).
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
