import SwiftUI

// MARK: - پنل دستیار (متصل به گفتگوهای ذخیره‌شده)

/// گفتگو دربارهٔ نشانکِ باز. هر پنل = یک «چت» پایدار که در صفحهٔ «گفتگوها»
/// قابل ادامه، تغییر نام، پاک‌کردن یا حذف است. تصمیم‌ها هم در «لاگ تصمیم» ثبت می‌شوند.
struct AssistantSheet: View {
    let bookmark: Bookmark

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lib = Library.shared
    @ObservedObject private var store = ChatStore.shared

    @State private var chatId: Int64 = 0
    @State private var pageContent: String?
    @State private var readingPage = false
    @State private var input = ""
    @State private var decisionNote = ""
    @State private var showDecisionField = false

    private var messages: [ChatMessage] {
        store.selectedId == chatId ? store.messages : []
    }

    private var lastDecision: Decision? {
        _ = store.decisionsVersion
        return store.decisions(for: bookmark.id).first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if messages.isEmpty {
                quickActions
                Divider()
            }
            conversation
            Divider()
            inputBar
        }
        .frame(minWidth: 720, idealWidth: 780, maxWidth: 920,
               minHeight: 520, idealHeight: 640, maxHeight: 800)
        .tint(AppTheme.accent)
        .environment(\.layoutDirection, L.direction)
        .environment(\.locale, Locale(identifier: "fa_IR"))
        .onAppear(perform: prepare)
    }

    private func prepare() {
        chatId = store.ensureChat(forBookmark: bookmark.id, title: bookmark.displayTitle)
        store.select(chatId)
        if pageContent == nil {
            pageContent = bookmark.content ?? lib.savedContent(id: bookmark.id)
        }
    }

    // MARK: سربرگ

    private var header: some View {
        HStack(spacing: 10) {
            FaviconView(path: bookmark.favicon, size: 26)

            VStack(alignment: .trailing, spacing: 2) {
                Text(L.tr("Assistant for This Bookmark"))
                    .font(.headline)
                Text(bookmark.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            if let decision = lastDecision {
                HStack(spacing: 4) {
                    Image(systemName: decision.verdict.icon).font(.system(size: 10))
                    Text("\(decision.verdict.label) · \(ChatsView.relative(decision.createdAt))")
                        .font(.caption2)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange.opacity(0.16)))
                .foregroundStyle(.orange)
                .help(decision.note.isBlank ? L.tr("Latest recorded decision") : decision.note)
            }

            if pageContent == nil || (pageContent ?? "").isBlank {
                Label(L.tr("Page text not read yet"), systemImage: "doc.questionmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(L.tr("The assistant reads the page on your first question."))
            }

            Button {
                dismiss()
                // اول شیت بسته شود، بعد صفحهٔ گفتگوها بیاید (وگرنه زیر شیت پنهان می‌ماند)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NotificationCenter.default.post(name: .showChats, object: nil)
                }
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
            }
            .buttonStyle(.borderless)
            .help(L.tr("All Chats"))

            Menu {
                Button(L.tr("Start Over (Clear Messages)")) {
                    store.clearMessages(chatId)
                }
                Button(L.tr("Delete This Chat"), role: .destructive) {
                    store.delete(chatId)
                    dismiss()
                }
                Divider()
                Button(L.tr("Log Decision…")) { showDecisionField = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help(L.tr("Chat Actions"))

            Button {
                dismiss()
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .popover(isPresented: $showDecisionField) {
            decisionPopover
        }
    }

    private var decisionPopover: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(L.tr("Record your decision"))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(L.tr("Note (optional)"), text: $decisionNote)
                .frame(width: 240)
            HStack(spacing: 6) {
                ForEach(Decision.Verdict.allCases) { verdict in
                    Button {
                        store.logDecision(bookmarkId: bookmark.id,
                                          verdict: verdict,
                                          note: decisionNote,
                                          chatId: chatId)
                        decisionNote = ""
                        showDecisionField = false
                        lib.notify(L.tr("Logged to decision log"))
                    } label: {
                        Label(verdict.label, systemImage: verdict.icon)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: پرسش‌های سریع

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 8)], spacing: 8) {
            ForEach(AIClient.QuickAction.all) { action in
                Button {
                    send(action.prompt)
                } label: {
                    Label(action.title, systemImage: action.icon)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.busy)
                .help(action.prompt)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: گفتگو

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty { emptyState }

                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                    }

                    if store.busy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(readingPage ? L.tr("Reading page…") : L.tr("Thinking…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .id("busy")
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
            .onChange(of: messages.count) { _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: store.busy) { _ in
                withAnimation { proxy.scrollTo("busy", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AppTheme.accent ?? .accentColor)
            Text(L.tr("Ask the assistant your question"))
                .font(.callout.weight(.semibold))
            Text(L.tr("The assistant checks this page against your profile and tells you whether it is useful for you."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if AIConfig.load().profile.isBlank {
                Text(L.tr("For more targeted answers, write your profile in Settings first."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if !isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                Text(message.content)
                    .textSelection(.enabled)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isUser ? (AppTheme.accent ?? .accentColor).opacity(0.16)
                                         : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(isUser ? 0.10 : 0.07), lineWidth: 1)
                    )

                if !isUser, message.id == messages.last?.id {
                    decisionBar
                }
            }
            .frame(maxWidth: 620, alignment: isUser ? .trailing : .leading)
            if isUser { Spacer(minLength: 40) }
        }
    }

    /// ثبت سریع تصمیم زیر پاسخ دستیار
    private var decisionBar: some View {
        HStack(spacing: 6) {
            Text(L.tr("Decision:"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ForEach(Decision.Verdict.allCases) { verdict in
                Button {
                    store.logDecision(bookmarkId: bookmark.id, verdict: verdict, chatId: chatId)
                    lib.notify(L.tf("Logged “%@”", verdict.label))
                } label: {
                    Text(verdict.label)
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            if let decision = lastDecision {
                Text(L.tf("Last: %@", decision.verdict.label))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: ورودی

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let error = store.errorText {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(L.tr("e.g. Is this monitor good for color design?"),
                          text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send(input) }

                Button {
                    send(input)
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

            Text(L.tr("This chat is saved; continue it later from Chats (⌘⇧C)."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: فرستادن

    private func send(_ raw: String) {
        let question = raw.trimmed
        guard !question.isEmpty, !store.busy, chatId != 0 else { return }
        input = ""
        store.errorText = nil
        let cfg = AIConfig.load()

        Task {
            var content = pageContent
            if content == nil || (content ?? "").isBlank {
                if let url = URL(string: bookmark.url) {
                    readingPage = true
                    let meta = await PageMeta.fetch(url)
                    if let text = meta.content, !text.isBlank {
                        content = text
                        pageContent = text
                    }
                    readingPage = false
                }
            }

            let system = AIClient.systemPrompt(profile: cfg.profile,
                                               bookmark: bookmark,
                                               pageContent: content)
            await store.ask(chatId: chatId, question: question, systemPrompt: system)
        }
    }
}
