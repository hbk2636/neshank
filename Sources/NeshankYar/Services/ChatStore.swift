import Foundation
import Combine

// MARK: - مخزن چت‌ها و تصمیم‌ها

/// چت‌ها، پیام‌ها و «لاگ تصمیم» را نگه می‌دارد (پایگاه‌دادهٔ محلی، همان فایل کتابخانه).
/// عمداً هیچ ارجاعی به Library ندارد تا در تست‌های بدون UI هم قابل استفاده باشد؛
/// زمینهٔ کتابخانه از بیرون (View) تزریق می‌شود.
@MainActor
final class ChatStore: ObservableObject {
    static let shared = ChatStore()

    @Published private(set) var chats: [Chat] = []
    @Published private(set) var messages: [ChatMessage] = []
    @Published var selectedId: Int64?
    @Published var search = "" { didSet { reloadChats() } }
    @Published var busy = false
    @Published var errorText: String?
    /// با هر ثبت/حذف تصمیم تغییر می‌کند تا نماها به‌روز شوند
    @Published private(set) var decisionsVersion = 0

    private let db: Database

    private init() {
        db = (try? Database(path: AppPaths.dbPath)) ?? (try! Database(path: ":memory:"))
        migrate()
        reloadChats()
        if selectedId == nil { selectedId = chats.first?.id }
        if let id = selectedId { loadMessages(chatId: id) }
    }

    private func migrate() {
        try? db.exec("""
        CREATE TABLE IF NOT EXISTS chats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL DEFAULT '',
            kind TEXT NOT NULL DEFAULT 'bookmark',
            bookmark_id INTEGER,
            pinned INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS chat_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            chat_id INTEGER NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            citations TEXT,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_msg_chat ON chat_messages(chat_id, id);
        CREATE TABLE IF NOT EXISTS decisions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bookmark_id INTEGER NOT NULL,
            chat_id INTEGER,
            verdict TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_dec_bm ON decisions(bookmark_id, created_at DESC);
        """)
    }

    // MARK: - چت‌ها

    func reloadChats() {
        let q = search.trimmed
        var sql = """
        SELECT c.id, c.title, c.kind, c.bookmark_id, c.pinned, c.created_at, c.updated_at,
               (SELECT COUNT(*) FROM chat_messages m WHERE m.chat_id = c.id) AS msg_count,
               (SELECT m.content FROM chat_messages m WHERE m.chat_id = c.id ORDER BY m.id DESC LIMIT 1) AS preview,
               b.title AS bm_title
        FROM chats c
        LEFT JOIN bookmarks b ON b.id = c.bookmark_id
        """
        var params: [SQLValue] = []
        if !q.isBlank {
            sql += """
             WHERE c.title LIKE ?
                OR b.title LIKE ?
                OR EXISTS (SELECT 1 FROM chat_messages m WHERE m.chat_id = c.id AND m.content LIKE ?)
            """
            let like = "%\(q)%"
            params = [.text(like), .text(like), .text(like)]
        }
        sql += " ORDER BY c.pinned DESC, c.updated_at DESC LIMIT 500"

        let rows = (try? db.rows(sql, params)) ?? []
        chats = rows.compactMap { row in
            guard let id = row.int("id") else { return nil }
            return Chat(
                id: id,
                title: row.textOrEmpty("title"),
                kind: Chat.Kind(rawValue: row.textOrEmpty("kind")) ?? .bookmark,
                bookmarkId: row.int("bookmark_id"),
                pinned: row.bool("pinned"),
                createdAt: Date(timeIntervalSince1970: row.double("created_at") ?? 0),
                updatedAt: Date(timeIntervalSince1970: row.double("updated_at") ?? 0),
                messageCount: Int(row.int("msg_count") ?? 0),
                preview: ChatText.clean(row.text("preview")),
                bookmarkTitle: row.text("bm_title")
            )
        }
    }

    func chat(_ id: Int64) -> Chat? { chats.first { $0.id == id } }

    /// چتِ یک نشانک (اگر باشد)
    func chat(forBookmark bookmarkId: Int64) -> Chat? {
        chats.first { $0.bookmarkId == bookmarkId && $0.kind == .bookmark }
    }

    @discardableResult
    func create(kind: Chat.Kind, bookmarkId: Int64?, title: String) -> Int64 {
        let now = Date().timeIntervalSince1970
        let id = (try? db.run(
            "INSERT INTO chats(title, kind, bookmark_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            [.text(title), .text(kind.rawValue),
             bookmarkId.map { SQLValue.int($0) } ?? .null,
             .real(now), .real(now)]
        )) ?? 0
        reloadChats()
        selectedId = id
        loadMessages(chatId: id)
        return id
    }

    /// چتِ نشانک را برمی‌گرداند و اگر نبود می‌سازد
    @discardableResult
    func ensureChat(forBookmark bookmarkId: Int64, title: String) -> Int64 {
        if let existing = chat(forBookmark: bookmarkId) { return existing.id }
        return create(kind: .bookmark, bookmarkId: bookmarkId, title: title)
    }

    func select(_ id: Int64?) {
        guard id != selectedId else { return }
        selectedId = id
        loadMessages(chatId: id)
    }

    func rename(_ id: Int64, title: String) {
        let clean = title.trimmed
        guard !clean.isEmpty else { return }
        _ = try? db.run("UPDATE chats SET title = ?, updated_at = ? WHERE id = ?",
                        [.text(clean), .real(Date().timeIntervalSince1970), .int(id)])
        reloadChats()
    }

    func setPinned(_ id: Int64, _ pinned: Bool) {
        _ = try? db.run("UPDATE chats SET pinned = ?, updated_at = ? WHERE id = ?",
                        [.int(pinned ? 1 : 0), .real(Date().timeIntervalSince1970), .int(id)])
        reloadChats()
    }

    /// «شروع از نو»: پیام‌ها پاک می‌شوند ولی چت (و عنوانش) می‌ماند
    func clearMessages(_ id: Int64) {
        _ = try? db.run("DELETE FROM chat_messages WHERE chat_id = ?", [.int(id)])
        _ = try? db.run("UPDATE chats SET updated_at = ? WHERE id = ?",
                        [.real(Date().timeIntervalSince1970), .int(id)])
        if selectedId == id { messages = [] }
        reloadChats()
    }

    func delete(_ id: Int64) {
        _ = try? db.run("DELETE FROM chat_messages WHERE chat_id = ?", [.int(id)])
        _ = try? db.run("DELETE FROM chats WHERE id = ?", [.int(id)])
        if selectedId == id {
            reloadChats()
            selectedId = chats.first?.id
            loadMessages(chatId: selectedId)
        } else {
            reloadChats()
        }
    }

    func deleteAll() {
        _ = try? db.run("DELETE FROM chat_messages")
        _ = try? db.run("DELETE FROM chats")
        chats = []
        messages = []
        selectedId = nil
    }

    // MARK: - پیام‌ها

    func loadMessages(chatId: Int64?) {
        guard let chatId else { messages = []; return }
        let rows = (try? db.rows(
            "SELECT id, chat_id, role, content, citations, created_at FROM chat_messages WHERE chat_id = ? ORDER BY id",
            [.int(chatId)]
        )) ?? []
        messages = rows.compactMap { row in
            guard let id = row.int("id") else { return nil }
            var cites: [ChatMessage.Citation] = []
            if let raw = row.text("citations"), let data = raw.data(using: .utf8) {
                cites = (try? JSONDecoder().decode([ChatMessage.Citation].self, from: data)) ?? []
            }
            return ChatMessage(
                id: id,
                chatId: row.int("chat_id") ?? 0,
                role: ChatMessage.Role(rawValue: row.textOrEmpty("role")) ?? .user,
                content: row.textOrEmpty("content"),
                citations: cites,
                createdAt: Date(timeIntervalSince1970: row.double("created_at") ?? 0)
            )
        }
    }

    @discardableResult
    func appendMessage(chatId: Int64,
                       role: ChatMessage.Role,
                       content: String,
                       citations: [ChatMessage.Citation] = []) -> ChatMessage {
        let now = Date().timeIntervalSince1970
        var citationsJSON: SQLValue = .null
        if !citations.isEmpty,
           let data = try? JSONEncoder().encode(citations),
           let text = String(data: data, encoding: .utf8) {
            citationsJSON = .text(text)
        }
        let id = (try? db.run(
            "INSERT INTO chat_messages(chat_id, role, content, citations, created_at) VALUES (?, ?, ?, ?, ?)",
            [.int(chatId), .text(role.rawValue), .text(content), citationsJSON, .real(now)]
        )) ?? 0
        _ = try? db.run("UPDATE chats SET updated_at = ? WHERE id = ?", [.real(now), .int(chatId)])

        let message = ChatMessage(id: id, chatId: chatId, role: role,
                                  content: content, citations: citations,
                                  createdAt: Date(timeIntervalSince1970: now))
        if selectedId == chatId { messages.append(message) }

        // عنوان خودکار: نخستین پرسش کاربر (عنوان پیش‌فرض ذخیره‌شده در هر زبانی بازنویسی می‌شود)
        if role == .user, let chat = chat(chatId),
           chat.title.isBlank || chat.title == "گفتگوی تازه" || chat.title == L.tr("New Library Chat") {
            rename(chatId, title: ChatText.autoTitle(content))
        } else {
            reloadChats()
        }
        return message
    }

    // MARK: - تصمیم‌ها

    func logDecision(bookmarkId: Int64,
                     verdict: Decision.Verdict,
                     note: String = "",
                     chatId: Int64? = nil) {
        let now = Date().timeIntervalSince1970
        _ = try? db.run(
            "INSERT INTO decisions(bookmark_id, chat_id, verdict, note, created_at) VALUES (?, ?, ?, ?, ?)",
            [.int(bookmarkId),
             chatId.map { SQLValue.int($0) } ?? .null,
             .text(verdict.rawValue), .text(note), .real(now)]
        )
        decisionsVersion += 1
    }

    func decisions(for bookmarkId: Int64, limit: Int = 20) -> [Decision] {
        let rows = (try? db.rows(
            "SELECT id, bookmark_id, verdict, note, created_at FROM decisions WHERE bookmark_id = ? ORDER BY id DESC LIMIT ?",
            [.int(bookmarkId), .int(Int64(limit))]
        )) ?? []
        return rows.compactMap(Self.decision)
    }

    func allDecisions(limit: Int = 60) -> [Decision] {
        let rows = (try? db.rows(
            "SELECT id, bookmark_id, verdict, note, created_at FROM decisions ORDER BY id DESC LIMIT ?",
            [.int(Int64(limit))]
        )) ?? []
        return rows.compactMap(Self.decision)
    }

    /// تصمیم‌های قدیمی‌تر از N روز (برای بازبینی در صفحهٔ «امروز»)
    func decisionsOlderThan(days: Int, limit: Int = 8) -> [Decision] {
        let cutoff = Date().timeIntervalSince1970 - Double(days) * 86_400
        let rows = (try? db.rows(
            "SELECT id, bookmark_id, verdict, note, created_at FROM decisions WHERE created_at < ? ORDER BY created_at DESC LIMIT ?",
            [.real(cutoff), .int(Int64(limit))]
        )) ?? []
        return rows.compactMap(Self.decision)
    }

    func deleteDecision(_ id: Int64) {
        _ = try? db.run("DELETE FROM decisions WHERE id = ?", [.int(id)])
        decisionsVersion += 1
    }

    private static func decision(_ row: DBRow) -> Decision? {
        guard let id = row.int("id"), let bm = row.int("bookmark_id") else { return nil }
        return Decision(
            id: id,
            bookmarkId: bm,
            verdict: Decision.Verdict(rawValue: row.textOrEmpty("verdict")) ?? .note,
            note: row.textOrEmpty("note"),
            createdAt: Date(timeIntervalSince1970: row.double("created_at") ?? 0)
        )
    }

    // MARK: - گفتگو با مدل

    /// تاریخچهٔ اخیر یک چت از پایگاه‌داده (نه از حافظهٔ نما — چون ممکن است چت دیگری انتخاب باشد)
    func recentMessages(chatId: Int64, limit: Int = 16) -> [(role: ChatMessage.Role, content: String)] {
        let rows = (try? db.rows(
            "SELECT role, content FROM chat_messages WHERE chat_id = ? ORDER BY id DESC LIMIT ?",
            [.int(chatId), .int(Int64(limit))]
        )) ?? []
        return rows.reversed().compactMap { row in
            guard let role = ChatMessage.Role(rawValue: row.textOrEmpty("role")) else { return nil }
            return (role, row.textOrEmpty("content"))
        }
    }

    /// پرسش + پاسخ را در چت ثبت می‌کند.
    /// - Parameters:
    ///   - systemPrompt: زمینه (نشانک یا کتابخانه) که View آماده می‌کند
    ///   - citations: منابع پیشنهادی برای نمایش زیر پاسخ (پرسش از کتابخانه)
    func ask(chatId: Int64,
             question: String,
             systemPrompt: String,
             citations: [ChatMessage.Citation] = [],
             historyLimit: Int = 16,
             maxTokens: Int = 2600) async {
        let text = question.trimmed
        guard !text.isBlank else { return }

        errorText = nil
        busy = true
        defer { busy = false }

        _ = appendMessage(chatId: chatId, role: .user, content: text)

        var outbound: [AIClient.Message] = [.system(systemPrompt)]
        for (role, content) in recentMessages(chatId: chatId, limit: historyLimit) {
            outbound.append(role == .user ? .user(content) : .assistant(content))
        }

        do {
            let answer = try await AIClient.chat(config: AIConfig.load(),
                                                 session: AIClient.newSession(),
                                                 messages: outbound,
                                                 maxTokens: maxTokens)
            _ = appendMessage(chatId: chatId, role: .assistant, content: answer, citations: citations)
        } catch {
            errorText = error.localizedDescription
            reloadChats()
        }
    }
}
