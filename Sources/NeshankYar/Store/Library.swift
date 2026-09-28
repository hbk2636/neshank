import Foundation
import AppKit
import Combine
import CryptoKit

// MARK: - کتابخانهٔ نشانک‌ها

@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    // Scopeهای سایدبار
    enum Scope: Hashable {
        case all, starred, trash, mindMaps
        /// پوشهٔ مجازی «بدون پوشه»: نشانک‌هایی که folder_id آن‌ها NULL است
        case unfiled
        case folder(Int64)
        case tag(String)

        /// نوع برای ذخیره در فیلترهای ذخیره‌شده
        var kind: String {
            switch self {
            case .all: return "all"
            case .starred: return "starred"
            case .trash: return "trash"
            case .mindMaps: return "mind_maps"
            case .unfiled: return "unfiled"
            case .folder: return "folder"
            case .tag: return "tag"
            }
        }

        /// مقدار همراه (شناسهٔ پوشه یا نام برچسب)
        var payload: String? {
            switch self {
            case .folder(let id): return String(id)
            case .tag(let name): return name
            default: return nil
            }
        }

        static func from(kind: String, payload: String?) -> Scope {
            switch kind {
            case "starred": return .starred
            case "trash": return .trash
            case "mind_maps": return .mindMaps
            case "unfiled": return .unfiled
            case "folder": return .folder(Int64(payload ?? "") ?? 0)
            case "tag": return .tag(payload ?? "")
            default: return .all
            }
        }
    }

    /// فیلتر ذخیره‌شده (جستجو + محدوده + مرتب‌سازی)
    struct SavedFilter: Identifiable, Hashable {
        var id: Int64
        var name: String
        var query: String
        var scope: Scope
        var sort: Sort
    }

    enum Sort: String, CaseIterable, Identifiable {
        case newest, oldest, title, site
        var id: String { rawValue }
        var label: String {
            switch self {
            case .newest: return L.tr("Newest")
            case .oldest: return L.tr("Oldest")
            case .title: return L.tr("Title")
            case .site: return L.tr("Website")
            }
        }
        var sql: String {
            switch self {
            case .newest: return "b.created_at DESC"
            case .oldest: return "b.created_at ASC"
            case .title: return "b.title COLLATE NOCASE ASC, b.created_at DESC"
            case .site: return "b.domain COLLATE NOCASE ASC, b.created_at DESC"
            }
        }
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case list, cards, boxes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .list: return L.tr("List")
            case .cards: return L.tr("Cards")
            case .boxes: return L.tr("Grid")
            }
        }
        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .cards: return "square.grid.2x2"
            case .boxes: return "square.grid.3x3"
            }
        }
    }

    // MARK: وضعیت منتشرشونده

    @Published var folders: [Folder] = []
    @Published var tags: [TagCount] = []
    @Published var results: [Bookmark] = []
    @Published var mindMaps: [MindMapRecord] = []
    @Published private(set) var mindMapCount = 0
    @Published var counts = Counts()
    @Published var folderCounts: [Int64: Int] = [:]
    /// شمارش نشانک‌های بدون پوشه (پوشهٔ مجازی «بدون پوشه»)
    @Published private(set) var unfiledCount = 0
    /// زبان رابط — تغییرش همهٔ نماها را دوباره رندر می‌کند
    @Published var language: AppLanguage = AppLanguage.current {
        didSet { AppLanguage.current = language }
    }
    @Published var savedFilters: [SavedFilter] = []

    @Published var scope: Scope = .all {
        didSet {
            guard scope != oldValue else { return }
            if scope == .mindMaps { selectedId = nil }
            else { selectedMindMapId = nil }
            reload()
        }
    }
    /// مرتب‌سازی (بین اجراها حفظ می‌شود)
    @Published var sort: Sort {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "sort") ; reload() }
    }
    @Published var query: String = "" { didSet { scheduleSearch() } }
    /// حالت نمایش (بین اجراها حفظ می‌شود — انتخاب کاربر)
    @Published var viewMode: ViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }

    @Published var selectedId: Int64?
    @Published var selectedMindMapId: Int64?
    @Published var editing: EditorTarget?
    @Published var notice: String?
    @Published var busy = false
    @Published var isChecking = false
    @Published var checkProgress: Double = 0
    @Published var lastCheck: Date?

    /// وضعیت «بازگردانی آخرین حذف» (⌘Z)
    @Published private(set) var canUndoDelete = false

    // ستون‌های مشترک SELECT (بدون content که سنگین است)
    static let cols = """
    b.id, b.url, b.title, b.note, b.domain, b.folder_id, b.starred,
    b.is_read, b.is_archived, b.is_dead, b.favicon, b.thumb, b.screenshot,
    b.deleted_at, b.created_at, b.updated_at, b.checked_at
    """

    // MARK: وضعیت داخلی

    private let db: Database
    /// مسیری که این نمونه با آن باز شده (برای بک‌آپ‌گیری و پیام خطا)
    private let dbPath: String
    private var ftsEnabled = false
    private var searchTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var lastDeleted: [Int64] = []

    /// اگر فایل دیتابیس واقعی باز نشده باشد و برنامه روی نسخهٔ حافظه‌ای کار کند،
    /// این خطا صریحاً در UI اعلام می‌شود (تغییرات در آن حالت ذخیره نمی‌شوند).
    @Published var storageError: String?

    // MARK: راه‌اندازی

    /// Internal path injection enables persistence tests to use a temporary database;
    /// production always uses the default Application Support path via `Library.shared`.
    init(databasePath: String = AppPaths.dbPath) {
        dbPath = databasePath
        do {
            db = try Database(path: databasePath)
        } catch {
            // آخرین پناه تا برنامه کرش نکند: دیتابیس حافظه‌ای — اما این وضعیت
            // هرگز بی‌صدا نمی‌ماند و بلافاصله در UI هشدار داده می‌شود.
            db = (try? Database(path: ":memory:")) ?? (try! Database(path: ":memory:"))
            storageError = L.tf(
                "The bookmarks database could not be opened — changes will NOT be saved. Path: %@ (%@)",
                databasePath, error.localizedDescription)
        }
        sort = Sort(rawValue: UserDefaults.standard.string(forKey: "sort") ?? "") ?? .newest
        viewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .list
        Self.migrate(db)
        ftsEnabled = Self.enableFTS(db)
        seedIfNeeded()
        purgeOldTrash()
        reload()
        refreshFilters()
        let saved = UserDefaults.standard.double(forKey: "lastCheck")
        lastCheck = saved > 0 ? Date(timeIntervalSince1970: saved) : nil
        Self.scheduleDailyBackup(sourcePath: dbPath)
    }

    /// حذف قطعی نشانک‌هایی که بیش از ۳۰ روز در زباله‌دان مانده‌اند
    private func purgeOldTrash() {
        let cutoff = Date().timeIntervalSince1970 - 30 * 86_400
        guard let rows = try? db.rows(
            "SELECT id FROM bookmarks WHERE deleted_at IS NOT NULL AND deleted_at < ?",
            [.real(cutoff)]
        ) else { return }
        for r in rows {
            guard let id = r.int("id") else { continue }
            _ = try? db.run("DELETE FROM bookmarks WHERE id = ?", [.int(id)])
            removeFromFTS(id)
        }
    }

    private static func migrate(_ db: Database) {
        try? db.exec("""
        CREATE TABLE IF NOT EXISTS folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
            pos INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            domain TEXT NOT NULL DEFAULT '',
            folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
            starred INTEGER NOT NULL DEFAULT 0,
            is_read INTEGER NOT NULL DEFAULT 0,
            is_archived INTEGER NOT NULL DEFAULT 0,
            is_dead INTEGER NOT NULL DEFAULT 0,
            favicon TEXT,
            thumb TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            checked_at REAL
        );
        CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE COLLATE NOCASE
        );
        CREATE TABLE IF NOT EXISTS bookmark_tags (
            bookmark_id INTEGER NOT NULL REFERENCES bookmarks(id) ON DELETE CASCADE,
            tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
            PRIMARY KEY (bookmark_id, tag_id)
        );
        CREATE INDEX IF NOT EXISTS idx_bm_folder ON bookmarks(folder_id);
        CREATE INDEX IF NOT EXISTS idx_bm_created ON bookmarks(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_bt_tag ON bookmark_tags(tag_id);
        CREATE TABLE IF NOT EXISTS saved_filters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            query TEXT NOT NULL DEFAULT '',
            scope_kind TEXT NOT NULL DEFAULT 'all',
            scope_payload TEXT,
            sort TEXT NOT NULL DEFAULT 'newest',
            created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS mind_maps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            source_url TEXT NOT NULL,
            normalized_url TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            mind_map_json TEXT NOT NULL,
            raw_markdown TEXT NOT NULL,
            model TEXT NOT NULL,
            language TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_mind_maps_created ON mind_maps(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_mind_maps_source ON mind_maps(normalized_url);
        """)

        // ستون‌های جدیدِ نسخهٔ ۱.۱ (ایدمبنت)
        Self.addColumn(db, table: "bookmarks", definition: "content TEXT")
        Self.addColumn(db, table: "bookmarks", definition: "screenshot TEXT")
        Self.addColumn(db, table: "bookmarks", definition: "deleted_at REAL")
        Self.addColumn(db, table: "folders", definition: "color TEXT")
        Self.addColumn(db, table: "folders", definition: "icon TEXT")
        // سنجاق‌کردن پوشه به بالای فهرست
        Self.addColumn(db, table: "folders", definition: "pinned INTEGER DEFAULT 0")
        try? db.exec("CREATE INDEX IF NOT EXISTS idx_bm_deleted ON bookmarks(deleted_at);")

        // تعمیر ارجاع‌های یتیم (اگر والدی پاک شده ولی فرزند مانده باشد، به ریشه برمی‌گردند)
        try? db.exec("""
        UPDATE folders SET parent_id = NULL
        WHERE parent_id IS NOT NULL AND parent_id NOT IN (SELECT id FROM folders);
        """)
        try? db.exec("""
        UPDATE bookmarks SET folder_id = NULL
        WHERE folder_id IS NOT NULL AND folder_id NOT IN (SELECT id FROM folders);
        """)

        // جدول mind_maps عمداً بدون seed است: نصب تازه هیچ نقشهٔ نمونه‌ای ندارد.
        // نقشه‌ها ردیف‌های مستقل‌اند و با هر تولید تازه یک شناسهٔ جدید می‌گیرند.
        // کش قدیمی مربوط به نسخهٔ آزمایشی و تک‌نقشه‌ای را حذف می‌کنیم.
        try? db.exec("DROP TABLE IF EXISTS mindmap_cache;")

        // MARK: مهاجرت‌های نسخه‌ای (PRAGMA user_version)
        // پایهٔ اسکیما همیشه idempotent بالا ساخته می‌شود؛ تغییرات جدیدِ خرابکننده
        // اینجا به‌صورت مرحلهٔ نسخه‌دار اضافه می‌شوند تا روی فایل‌های قدیمی هم امن باشند.
        let current = (try? db.scalarInt("PRAGMA user_version")) ?? 0
        let migrations: [Int: (Database) throws -> Void] = [
            // ۲: شمارش گرهٔ نقشه به‌صورت ستون — تا فهرست مجبور نباشد JSON کل ردیف‌ها را بخواند
            2: { db in
                Self.addColumn(db, table: "mind_maps", definition: "node_count INTEGER NOT NULL DEFAULT 0")
                let rows = (try? db.rows("SELECT id, mind_map_json FROM mind_maps WHERE node_count = 0")) ?? []
                for r in rows {
                    guard let id = r.int("id") else { continue }
                    let count = MindMapRecord.countNodes(in: r.textOrEmpty("mind_map_json"))
                    _ = try? db.run("UPDATE mind_maps SET node_count = ? WHERE id = ?",
                                    [.int(Int64(count)), .int(id)])
                }
            },
        ]
        var version = current
        for (target, apply) in migrations.sorted(by: { $0.key < $1.key }) where target > current {
            do {
                try apply(db)
                version = Int64(target)
            } catch {
                // مهاجرت ناموفق نسخه را جلو نمی‌برد؛ اجرای بعدی دوباره تلاش می‌کند
                print("[NeshankYar] migration \(target) failed: \(error)")
                break
            }
        }
        if version != current {
            try? db.exec("PRAGMA user_version = \(version)")
        }
    }

    private static func addColumn(_ db: Database, table: String, definition: String) {
        let name = definition.split(separator: " ").first.map(String.init) ?? definition
        let existing = (try? db.rows("PRAGMA table_info(\(table))")) ?? []
        guard !existing.contains(where: { $0.text("name") == name }) else { return }
        try? db.exec("ALTER TABLE \(table) ADD COLUMN \(definition)")
    }

    // MARK: بک‌آپ دیتابیس

    /// زمان‌بندی بک‌آپ روزانه — فقط مقادیر Sendable به تسک پس‌زمینه می‌روند.
    private nonisolated static func scheduleDailyBackup(sourcePath: String) {
        #if DEBUG
        // در تست‌های یکپارچگی، بک‌آپ خودکار به مسیر واقعی کاربر نرود
        if ProcessInfo.processInfo.environment["NESHANKYAR_TEST_DATA_DIR"] != nil { return }
        #endif
        let backupsDirectory = AppPaths.backupsDir.path
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 4_000_000_000)   // تا افتتاح برنامه مزاحم نشود
            Library.dailyBackupIfNeeded(sourcePath: sourcePath, backupsDirectory: backupsDirectory)
        }
    }

    /// روزانه یک‌بار اسنپ‌شات می‌گیرد و ۵ نسخهٔ آخرِ خودکار را نگه می‌دارد
    /// (بک‌آپ‌های دستی کاربر هرگز خودکار حذف نمی‌شوند؛ هر نسخه در حد چند صد کیلوبایت).
    nonisolated static func dailyBackupIfNeeded(sourcePath: String, backupsDirectory: String, keep: Int = 5) {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: "lastAutoBackup") as? Date,
           Calendar.current.isDateInToday(last) { return }
        do {
            _ = try Database.backup(sourcePath: sourcePath, directory: backupsDirectory, prefix: "auto")
            defaults.set(Date(), forKey: "lastAutoBackup")
            pruneBackups(directory: backupsDirectory, prefix: "neshank-auto-", keep: keep)
        } catch {
            // بک‌آپ بهترین‌تلاش است؛ خطا لاگ می‌شود و اجرای بعدی دوباره تلاش می‌کند
            print("[NeshankYar] auto-backup failed: \(error)")
        }
    }

    /// بک‌آپ فوری (دکمهٔ تنظیمات) — مسیر فایل ساخته‌شده را برمی‌گرداند.
    @discardableResult
    func backUpNow() throws -> URL {
        try Database.backup(sourcePath: dbPath, directory: AppPaths.backupsDir.path, prefix: "manual")
    }

    /// حذف نسخه‌های قدیمی بک‌آپ با همان پیشوند تا فقط `keep` تای آخر بماند
    nonisolated static func pruneBackups(directory: String, prefix: String, keep: Int) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: directory) else { return }
        let files = items
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".sqlite3") }
            .sorted(by: >)
        for old in files.dropFirst(keep) {
            try? fm.removeItem(atPath: (directory as NSString).appendingPathComponent(old))
        }
    }

    @discardableResult
    private static func enableFTS(_ db: Database) -> Bool {
        do {
            // اگر جدول FTS قدیمی است (بدون content) از نو ساخته می‌شود
            let hasContent = (try? db.rows("SELECT content FROM fts LIMIT 1")) != nil
            if !hasContent {
                try? db.exec("DROP TABLE IF EXISTS fts")
            }
            try db.exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5(
                title, note, url, domain, content,
                tokenize = 'unicode61 remove_diacritics 2'
            );
            """)
            let count = try db.scalarInt("SELECT COUNT(*) FROM fts") ?? 0
            if count == 0 {
                try db.exec("""
                INSERT INTO fts(rowid, title, note, url, domain, content)
                SELECT id, title, note, url, domain, COALESCE(content, '') FROM bookmarks;
                """)
            }
            return true
        } catch {
            return false
        }
    }

    private func seedIfNeeded() {
        let n = (try? db.scalarInt("SELECT COUNT(*) FROM folders")) ?? 0
        guard n == 0 else { return }
        // نام‌ها به زبان رابط برنامه؛ در دیتابیس ذخیره می‌شوند ولی بومی‌سازی بعدی
        // از طریق نمایش، و تغییر نام کاربر همیشه ممکن است.
        for (i, name) in [L.tr("Reading List"), L.tr("Work"), L.tr("Entertainment")].enumerated() {
            _ = try? db.run("INSERT INTO folders(name, pos) VALUES (?, ?)", [.text(name), .int(Int64(i))])
        }
    }

    // MARK: - بارگذاری

    func reload() {
        if scope == .mindMaps {
            results = []
            selectedId = nil
            reloadMindMaps()
            refreshCounts()
            refreshFolders()
            refreshTags()
            return
        }
        selectedMindMapId = nil
        mindMaps = []
        do {
            var sql = """
            SELECT \(Self.cols)
            FROM bookmarks b WHERE 1=1
            """
            var params: [SQLValue] = []

            switch scope {
            case .trash:
                sql += " AND b.deleted_at IS NOT NULL"
            case .all:
                sql += " AND b.is_archived = 0 AND b.deleted_at IS NULL"
            case .starred:
                sql += " AND b.starred = 1 AND b.is_archived = 0 AND b.deleted_at IS NULL"
            case .folder(let fid):
                sql += " AND b.folder_id = ? AND b.is_archived = 0 AND b.deleted_at IS NULL"
                params.append(.int(fid))
            case .unfiled:
                sql += " AND b.folder_id IS NULL AND b.is_archived = 0 AND b.deleted_at IS NULL"
            case .tag(let name):
                sql += """
                 AND b.is_archived = 0 AND b.deleted_at IS NULL AND b.id IN (
                    SELECT bt.bookmark_id FROM bookmark_tags bt
                    JOIN tags t ON t.id = bt.tag_id WHERE t.name = ?
                )
                """
                params.append(.text(name))
            case .mindMaps:
                // این case پیش از ساخت query مدیریت می‌شود؛ برای exhaustiveness.
                sql += " AND 1=0"
            }

            let q = query.trimmed
            if !q.isEmpty {
                let like = "%\(q)%"
                var pred = ""
                if ftsEnabled {
                    let tokens = q.split(whereSeparator: { $0.isWhitespace })
                        .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                        .joined(separator: " ")
                    do {
                        _ = try db.rows("SELECT rowid FROM fts WHERE fts MATCH ? LIMIT 1", [.text(tokens)])
                        pred = """
                        AND (
                          b.id IN (SELECT rowid FROM fts WHERE fts MATCH ?)
                          OR b.id IN (
                            SELECT bt.bookmark_id FROM bookmark_tags bt
                            JOIN tags t ON t.id = bt.tag_id WHERE t.name LIKE ?
                          )
                        )
                        """
                        params.append(.text(tokens))
                        params.append(.text(like))
                    } catch {
                        pred = ""
                    }
                }
                if pred.isEmpty {
                    pred = """
                    AND (
                      b.title LIKE ? OR b.note LIKE ? OR b.url LIKE ? OR b.domain LIKE ?
                      OR b.id IN (
                        SELECT bt.bookmark_id FROM bookmark_tags bt
                        JOIN tags t ON t.id = bt.tag_id WHERE t.name LIKE ?
                      )
                    )
                    """
                    params.append(contentsOf: [.text(like), .text(like), .text(like), .text(like), .text(like)])
                }
                sql += pred
            }

            sql += " ORDER BY " + sort.sql + " LIMIT 2000"

            var items = try db.rows(sql, params).map(Bookmark.init(row:))

            // برچسب‌ها
            let pairs = try db.rows("""
                SELECT bt.bookmark_id AS bid, t.name AS name
                FROM bookmark_tags bt JOIN tags t ON t.id = bt.tag_id
                """)
            var tagMap: [Int64: [String]] = [:]
            for p in pairs {
                if let bid = p.int("bid"), let name = p.text("name") {
                    tagMap[bid, default: []].append(name)
                }
            }
            for i in items.indices {
                items[i].tags = tagMap[items[i].id] ?? []
            }

            results = items

            // انتخاب قبلی اگر دیگر در نتایج نیست، لغو می‌شود تا پنل جزئیات
            // خودکار باز نماند (پنل فقط با کلیک کاربر باز می‌شود)
            if let sel = selectedId, !items.contains(where: { $0.id == sel }) {
                selectedId = nil
            }

            refreshCounts()
            refreshFolders()
            refreshTags()
        } catch {
            notify(L.tf("Failed to load: %@", error.localizedDescription))
        }
    }

    private func refreshCounts() {
        guard let row = try? db.rows("""
            SELECT
              COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) AS total,
              COALESCE(SUM(CASE WHEN starred=1 AND is_archived=0 AND deleted_at IS NULL THEN 1 ELSE 0 END),0) AS starred,
              COALESCE(SUM(CASE WHEN is_read=0 AND is_archived=0 AND deleted_at IS NULL THEN 1 ELSE 0 END),0) AS unread,
              COALESCE(SUM(CASE WHEN is_dead=1 AND is_archived=0 AND deleted_at IS NULL THEN 1 ELSE 0 END),0) AS dead,
              COALESCE(SUM(CASE WHEN is_archived=1 AND deleted_at IS NULL THEN 1 ELSE 0 END),0) AS archived,
              COALESCE(SUM(CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END),0) AS trash
            FROM bookmarks
        """).first else { return }
        counts = Counts(
            all: Int(row.int("total") ?? 0),
            starred: Int(row.int("starred") ?? 0),
            unread: Int(row.int("unread") ?? 0),
            dead: Int(row.int("dead") ?? 0),
            archived: Int(row.int("archived") ?? 0),
            trash: Int(row.int("trash") ?? 0)
        )
        mindMapCount = Int((try? db.scalarInt("SELECT COUNT(*) FROM mind_maps")) ?? 0)

        var fc: [Int64: Int] = [:]
        if let rows = try? db.rows(
            """
            SELECT folder_id AS fid, COUNT(*) AS c FROM bookmarks
            WHERE is_archived=0 AND deleted_at IS NULL AND folder_id IS NOT NULL
            GROUP BY folder_id
            """
        ) {
            for r in rows {
                if let fid = r.int("fid") { fc[fid] = Int(r.int("c") ?? 0) }
            }
        }
        folderCounts = fc
        unfiledCount = Int((try? db.scalarInt(
            "SELECT COUNT(*) FROM bookmarks WHERE folder_id IS NULL AND is_archived=0 AND deleted_at IS NULL"
        )) ?? 0)
    }

    // MARK: - نقشه‌های ذهنی (رکوردهای مستقل در کتابخانه)

    private func reloadMindMaps() {
        let q = query.trimmed
        let rows: [DBRow]
        if q.isEmpty {
            // فهرست JSON کامل را نمی‌خواهد (سنگین) — فقط شمارش گره
            rows = (try? db.rows("""
                SELECT id, title, source_url, normalized_url, content_hash,
                       raw_markdown, model, language, node_count, created_at, updated_at
                FROM mind_maps ORDER BY created_at DESC LIMIT 2000
                """)) ?? []
        } else {
            let like = "%\(q)%"
            rows = (try? db.rows("""
                SELECT id, title, source_url, normalized_url, content_hash,
                       raw_markdown, model, language, node_count, created_at, updated_at
                FROM mind_maps
                WHERE title LIKE ? OR source_url LIKE ? OR raw_markdown LIKE ?
                ORDER BY created_at DESC LIMIT 2000
                """, [.text(like), .text(like), .text(like)])) ?? []
        }
        mindMaps = rows.map(MindMapRecord.init(row:))
        if let id = selectedMindMapId, !mindMaps.contains(where: { $0.id == id }) {
            selectedMindMapId = nil
        }
    }

    func mindMap(id: Int64) -> MindMapRecord? {
        guard let row = try? db.rows("""
            SELECT id, title, source_url, normalized_url, content_hash, mind_map_json,
                   raw_markdown, model, language, node_count, created_at, updated_at
            FROM mind_maps WHERE id = ? LIMIT 1
            """, [.int(id)]).first else { return nil }
        return MindMapRecord(row: row)
    }

    /// افزودن رکورد جدید — URL تکراری را عمداً overwrite نمی‌کنیم.
    @discardableResult
    func createMindMap(title: String, sourceURL: String, markdown: String,
                       json: String, model: String, language: String) -> MindMapRecord? {
        let now = Date().timeIntervalSince1970
        let normalized = URLNormalizer.url(sourceURL)?.absoluteString ?? sourceURL
        let hash = SHA256.hash(data: Data(markdown.utf8)).map { String(format: "%02x", $0) }.joined()
        do {
            let id = try db.run("""
                INSERT INTO mind_maps(title, source_url, normalized_url, content_hash,
                                      mind_map_json, raw_markdown, model, language, node_count,
                                      created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(title), .text(sourceURL), .text(normalized), .text(hash), .text(json),
                      .text(markdown), .text(model), .text(language),
                      .int(Int64(MindMapRecord.countNodes(in: json))),
                      .real(now), .real(now)])
            refreshCounts()
            if scope == .mindMaps {
                reloadMindMaps()
                selectedMindMapId = id
            }
            return mindMap(id: id)
        } catch {
            notify(L.tf("Failed to save mind map: %@", error.localizedDescription))
            return nil
        }
    }

    /// ذخیرهٔ تغییرات روی همان نقشهٔ انتخاب‌شده؛ تولید مجدد از این مسیر استفاده نمی‌کند.
    @discardableResult
    func updateMindMap(id: Int64, title: String, sourceURL: String, markdown: String,
                       json: String, model: String, language: String) -> Bool {
        let normalized = URLNormalizer.url(sourceURL)?.absoluteString ?? sourceURL
        let hash = SHA256.hash(data: Data(markdown.utf8)).map { String(format: "%02x", $0) }.joined()
        do {
            _ = try db.run("""
                UPDATE mind_maps SET title = ?, source_url = ?, normalized_url = ?, content_hash = ?,
                    mind_map_json = ?, raw_markdown = ?, model = ?, language = ?,
                    node_count = ?, updated_at = ?
                WHERE id = ?
                """, [.text(title), .text(sourceURL), .text(normalized), .text(hash), .text(json),
                      .text(markdown), .text(model), .text(language),
                      .int(Int64(MindMapRecord.countNodes(in: json))),
                      .real(Date().timeIntervalSince1970),
                      .int(id)])
            if scope == .mindMaps { reloadMindMaps() }
            return true
        } catch {
            notify(L.tf("Failed to save mind map changes: %@", error.localizedDescription))
            return false
        }
    }

    func deleteMindMaps(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        do {
            try db.transaction {
                for id in ids { _ = try db.run("DELETE FROM mind_maps WHERE id = ?", [.int(id)]) }
            }
            if let selectedMindMapId, ids.contains(selectedMindMapId) { self.selectedMindMapId = nil }
            refreshCounts()
            if scope == .mindMaps { reloadMindMaps() }
            notify(L.tf("%@ mind maps deleted from the library; original bookmarks untouched", Digits.fa(ids.count)))
        } catch {
            notify(L.tf("Failed to delete mind map: %@", error.localizedDescription))
        }
    }

    private func refreshFolders() {
        guard let rows = try? db.rows(
            "SELECT id, name, parent_id, color, icon, pinned FROM folders ORDER BY pos, name COLLATE NOCASE"
        ) else { return }
        let flat: [Folder] = rows.map {
            Folder(
                id: $0.int("id") ?? 0,
                name: $0.textOrEmpty("name"),
                parentId: $0.int("parent_id"),
                color: $0.text("color"),
                icon: $0.text("icon"),
                pinned: ($0.int("pinned") ?? 0) != 0
            )
        }
        folders = buildTree(flat)
    }

    private func buildTree(_ flat: [Folder]) -> [Folder] {
        var childrenMap: [Int64: [Folder]] = [:]
        for f in flat {
            if let p = f.parentId {
                childrenMap[p, default: []].append(f)
            }
        }
        // در هر سطح، پوشه‌های سنجاق‌شده بالای بقیه می‌آیند
        func order(_ a: Folder, _ b: Folder) -> Bool {
            if a.pinned != b.pinned { return a.pinned }
            return a.name < b.name
        }
        func make(_ f: Folder) -> Folder {
            var copy = f
            copy.children = (childrenMap[f.id] ?? []).sorted(by: order).map(make)
            return copy
        }
        return flat.filter { $0.parentId == nil }.sorted(by: order).map(make)
    }

    /// فهرست تخت پوشه‌ها برای Picker
    func folderOptions() -> [FolderOption] {
        var out: [FolderOption] = [FolderOption(id: 0, label: L.tr("Unfiled"), depth: 0)]
        func walk(_ list: [Folder], depth: Int) {
            for f in list {
                out.append(FolderOption(id: f.id, label: String(repeating: "　", count: depth) + f.name, depth: depth))
                walk(f.children, depth: depth + 1)
            }
        }
        walk(folders, depth: 0)
        return out
    }

    private func refreshTags() {
        guard let rows = try? db.rows("""
            SELECT t.id AS id, t.name AS name,
                   COALESCE(SUM(CASE WHEN b.is_archived=0 AND b.deleted_at IS NULL THEN 1 ELSE 0 END),0) AS c
            FROM tags t
            LEFT JOIN bookmark_tags bt ON bt.tag_id = t.id
            LEFT JOIN bookmarks b ON b.id = bt.bookmark_id
            GROUP BY t.id
            HAVING c > 0
            ORDER BY t.name COLLATE NOCASE
        """) else { return }
        tags = rows.map {
            TagCount(id: $0.int("id") ?? 0, name: $0.textOrEmpty("name"), count: Int($0.int("c") ?? 0))
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let work = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard let self, !Task.isCancelled else { return }
            self.reload()
        }
        searchTask = work
    }

    // MARK: - اعلان

    func notify(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.notice = nil
        }
    }

    /// اجرای یک فرمان نوشتن DB با گزارش خطا — جایگزین `try?` بی‌صدایی که
    /// از دست رفتن داده را پنهان می‌کرد. `context` برای پیام خطای کاربر است.
    @discardableResult
    private func runWrite(_ sql: String, _ params: [SQLValue] = [], context: String) -> Bool {
        do {
            _ = try db.run(sql, params)
            return true
        } catch {
            notify(L.tf("Save failed: %@ — %@", L.tr(context), error.localizedDescription))
            return false
        }
    }

    // MARK: - افزودن / ویرایش

    func add(rawURL: String, title: String, note: String, folderId: Int64?,
             tags tagNames: [String], fetchMeta: Bool) async {
        guard let url = URLNormalizer.url(rawURL) else {
            notify(L.tr("Invalid URL"))
            return
        }
        busy = true
        defer { busy = false }

        let now = Date().timeIntervalSince1970
        var newId: Int64 = 0
        do {
            newId = try db.run("""
                INSERT INTO bookmarks(url, title, note, domain, folder_id, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, [
                    .text(url.absoluteString),
                    .text(title.trimmed),
                    .text(note.trimmed),
                    .text(URLNormalizer.domain(url)),
                    folderId.map { .int($0) } ?? .null,
                    .real(now),
                    .real(now)
                ])
        } catch {
            notify(L.tf("Failed to save: %@", error.localizedDescription))
            return
        }

        setTags(bookmarkId: newId, names: tagNames)

        let prefs = UserDefaults.standard
        if fetchMeta {
            let meta = await PageMeta.fetch(url)
            var finalTitle = title.trimmed
            if finalTitle.isEmpty { finalTitle = meta.title?.trimmed ?? "" }
            if finalTitle.isEmpty { finalTitle = URLNormalizer.domain(url) }
            var finalNote = note.trimmed
            if finalNote.isEmpty { finalNote = meta.description?.trimmed ?? "" }

            var favPath: String?
            if let fu = meta.faviconURL, let (data, ext) = await PageMeta.download(fu) {
                favPath = AppPaths.save(data, folder: "Favicons", key: url.absoluteString, ext: ext)
            }
            var thumbPath: String?
            if let iu = meta.imageURL, let (data, ext) = await PageMeta.download(iu, maxBytes: 1_500_000) {
                thumbPath = AppPaths.save(data, folder: "Thumbnails", key: url.absoluteString, ext: ext)
            }

            var content: String?
            if prefs.object(forKey: "saveContent") as? Bool ?? true {
                content = meta.content
            }

            _ = try? db.run("""
                UPDATE bookmarks SET title = ?, note = ?, favicon = ?, thumb = ?,
                       content = COALESCE(?, content), updated_at = ? WHERE id = ?
                """, [
                    .text(finalTitle),
                    .text(finalNote),
                    favPath.map { .text($0) } ?? .null,
                    thumbPath.map { .text($0) } ?? .null,
                    content.map { .text($0) } ?? .null,
                    .real(Date().timeIntervalSince1970),
                    .int(newId)
                ])
        }

        if let b = bookmark(id: newId) { indexFTS(b) }
        reload()
        selectedId = newId
        notify(L.tr("Bookmark saved"))

        // عکس صفحه در پس‌زمینه گرفته می‌شود تا افزودن سریع بماند
        if fetchMeta, prefs.bool(forKey: "captureScreenshot") {
            Task { [weak self] in
                await self?.captureScreenshot(id: newId)
            }
        }
    }

    func update(_ target: Bookmark, url rawURL: String, title: String, note: String,
                folderId: Int64?, tags tagNames: [String]) {
        let cleanURL = URLNormalizer.url(rawURL)?.absoluteString ?? target.url
        let u = URL(string: cleanURL)
        do {
            try db.run("""
                UPDATE bookmarks SET url=?, title=?, note=?, domain=?, folder_id=?, updated_at=? WHERE id=?
                """, [
                    .text(cleanURL),
                    .text(title.trimmed),
                    .text(note.trimmed),
                    .text(u.map(URLNormalizer.domain) ?? target.domain),
                    folderId.map { .int($0) } ?? .null,
                    .real(Date().timeIntervalSince1970),
                    .int(target.id)
                ])
            setTags(bookmarkId: target.id, names: tagNames)
            if let b = bookmark(id: target.id) { indexFTS(b) }
            reload()
        } catch {
            notify(L.tf("Failed to edit: %@", error.localizedDescription))
        }
    }

    // MARK: - حذف (نرم) / بازگردانی / زباله‌دان

    /// حذف نرم: نشانک به زباله‌دان می‌رود و با ⌘Z برمی‌گردد
    func delete(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let stamp = Date().timeIntervalSince1970
        do {
            for id in ids {
                try db.run("UPDATE bookmarks SET deleted_at = ?, updated_at = ? WHERE id = ?", [
                    .real(stamp), .real(stamp), .int(id)
                ])
            }
            if let sel = selectedId, ids.contains(sel) { selectedId = nil }
            lastDeleted = ids
            canUndoDelete = true
            reload()
            notify(L.tf("%@ bookmarks moved to Trash (⌘Z to undo)", Digits.fa(ids.count)))
        } catch {
            notify(L.tf("Failed to delete: %@", error.localizedDescription))
        }
    }

    /// بازگردانی آخرین حذف (میان‌بر ⌘Z)
    func undoDelete() {
        guard canUndoDelete, !lastDeleted.isEmpty else { return }
        let ids = lastDeleted
        restore(ids: ids)
        lastDeleted = []
        canUndoDelete = false
    }

    /// بازگردانی از زباله‌دان
    func restore(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let stamp = Date().timeIntervalSince1970
        var failed = 0
        for id in ids {
            if !runWrite("UPDATE bookmarks SET deleted_at = NULL, updated_at = ? WHERE id = ?",
                         [.real(stamp), .int(id)], context: "Restore") { failed += 1 }
        }
        reload()
        if failed == 0 {
            notify(L.tf("%@ bookmarks restored", Digits.fa(ids.count)))
        }
    }

    /// حذف قطعی همهٔ محتوای زباله‌دان
    func emptyTrash() {
        guard let rows = try? db.rows("SELECT id, favicon, thumb, screenshot FROM bookmarks WHERE deleted_at IS NOT NULL") else {
            notify(L.tr("Trash is empty"))
            return
        }
        var n = 0, failed = 0
        for r in rows {
            guard let id = r.int("id") else { continue }
            for key in ["favicon", "thumb", "screenshot"].compactMap({ r.text($0) }) {
                try? FileManager.default.removeItem(atPath: key)
            }
            if !runWrite("DELETE FROM bookmarks WHERE id = ?", [.int(id)], context: "Empty Trash") { failed += 1 }
            removeFromFTS(id)
            n += 1
        }
        reload()
        if failed == 0 {
            notify(L.tf("%@ bookmarks deleted permanently", Digits.fa(n)))
        }
    }

    /// حذف قطعی یک نشانک از زباله‌دان
    func purge(ids: [Int64]) {
        for id in ids {
            if let b = bookmark(id: id) {
                for path in [b.favicon, b.thumb, b.screenshot].compactMap({ $0 }) {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            runWrite("DELETE FROM bookmarks WHERE id = ?", [.int(id)], context: "Delete Permanently")
            removeFromFTS(id)
        }
        if let sel = selectedId, ids.contains(sel) { selectedId = nil }
        reload()
        notify(L.tf("%@ bookmarks deleted permanently", Digits.fa(ids.count)))
    }

    // MARK: - پرچم‌ها

    private func setFlag(_ id: Int64, column: String, value: Bool) {
        runWrite("UPDATE bookmarks SET \(column) = ?, updated_at = ? WHERE id = ?", [
            .int(value ? 1 : 0),
            .real(Date().timeIntervalSince1970),
            .int(id)
        ], context: "Update")
        reload()
    }

    func setStarred(_ id: Int64, _ v: Bool) { setFlag(id, column: "starred", value: v) }
    func setRead(_ id: Int64, _ v: Bool) { setFlag(id, column: "is_read", value: v) }
    func setArchived(_ id: Int64, _ v: Bool) { setFlag(id, column: "is_archived", value: v) }

    /// اعمال یک پرچم روی چند نشانک با یک فرمان (برای انتخاب چندتایی)
    func setFlagBulk(_ ids: [Int64], column: String, value: Bool) {
        guard !ids.isEmpty else { return }
        let allowed = ["starred", "is_read", "is_archived", "is_dead"]
        guard allowed.contains(column) else { return }
        for id in ids {
            runWrite("UPDATE bookmarks SET \(column) = ?, updated_at = ? WHERE id = ?", [
                .int(value ? 1 : 0),
                .real(Date().timeIntervalSince1970),
                .int(id)
            ], context: "Update")
        }
        reload()
    }

    /// افزودن برچسب به چند نشانک
    func addTagBulk(_ ids: [Int64], name: String) {
        for id in ids { addTag(bookmarkId: id, name: name) }
        notify(L.tf("Tag “%@” added", name))
    }

    func updateNote(_ id: Int64, _ note: String) {
        runWrite("UPDATE bookmarks SET note = ?, updated_at = ? WHERE id = ?", [
            .text(note.trimmed),
            .real(Date().timeIntervalSince1970),
            .int(id)
        ], context: "Save Note")
        reload()
    }

    func setFolder(_ ids: [Int64], folderId: Int64?) {
        for id in ids {
            runWrite("UPDATE bookmarks SET folder_id = ?, updated_at = ? WHERE id = ?", [
                folderId.map { .int($0) } ?? .null,
                .real(Date().timeIntervalSince1970),
                .int(id)
            ], context: "Move to Folder")
        }
        reload()
    }

    // MARK: - پوشه‌ها

    func addFolder(name: String, parent: Int64?) {
        let n = name.trimmed
        guard !n.isEmpty else { return }
        let pos = Int64(((try? db.scalarInt("SELECT COALESCE(MAX(pos),0) FROM folders")) ?? 0) + 1)
        do {
            let id = try db.run("INSERT INTO folders(name, parent_id, pos) VALUES (?, ?, ?)", [
                .text(n), parent.map { .int($0) } ?? .null, .int(pos)
            ])
            reload()
            scope = .folder(id)
        } catch {
            notify(L.tf("Failed to create folder: %@", error.localizedDescription))
        }
    }

    func renameFolder(id: Int64, name: String) {
        let n = name.trimmed
        guard !n.isEmpty else { return }
        if runWrite("UPDATE folders SET name = ? WHERE id = ?", [.text(n), .int(id)], context: "Rename Folder") {
            reload()
        }
    }

    func deleteFolder(id: Int64) {
        let flat = flattenFolders(folders)
        guard let target = flat.first(where: { $0.id == id }) else { return }
        // زیرپوشه‌ها یک سطح بالا می‌آیند (حذف نمی‌شوند) و نشانک‌های خود پوشه بی‌پوشه می‌شوند
        let newParent: SQLValue = target.parentId.map { .int($0) } ?? .null
        var failed = false
        failed = !runWrite("UPDATE folders SET parent_id = ? WHERE parent_id = ?",
                        [newParent, .int(id)], context: "Delete Folder") || failed
        failed = !runWrite("UPDATE bookmarks SET folder_id = NULL WHERE folder_id = ?",
                        [.int(id)], context: "Delete Folder") || failed
        failed = !runWrite("DELETE FROM folders WHERE id = ?", [.int(id)], context: "Delete Folder") || failed
        if failed { return }
        if case .folder(let f) = scope {
            if f == id || isDescendant(folderId: f, of: id) {
                scope = .all
            } else {
                reload()
            }
        } else {
            reload()
        }
        notify(L.tr("Folder deleted; subfolders moved up one level"))
    }

    /// آیا پوشه، نوادهٔ جد مشخص‌شده است؟
    private func isDescendant(folderId: Int64, of ancestor: Int64) -> Bool {
        var parentOf: [Int64: Int64] = [:]
        for f in flattenFolders(folders) {
            if let p = f.parentId { parentOf[f.id] = p }
        }
        var cur: Int64? = folderId
        while let c = cur {
            if c == ancestor { return true }
            cur = parentOf[c]
        }
        return false
    }

    /// سنجاق‌کردن پوشه به بالای فهرست (یا برداشتن سنجاق)
    func setFolderPinned(id: Int64, pinned: Bool) {
        if runWrite("UPDATE folders SET pinned = ? WHERE id = ?",
                    [.int(pinned ? 1 : 0), .int(id)], context: "Pin to Top") {
            refreshFolders()
        }
    }

    /// رنگ سفارشی پوشه (nil = بازگشت به پیش‌فرض)
    func setFolderColor(id: Int64, hex: String?) {
        if let hex {
            runWrite("UPDATE folders SET color = ? WHERE id = ?", [.text(hex), .int(id)], context: "Folder Appearance")
        } else {
            runWrite("UPDATE folders SET color = NULL WHERE id = ?", [.int(id)], context: "Folder Appearance")
        }
        reload()
    }

    /// آیکون سفارشی پوشه (nil = پیش‌فرض)
    func setFolderIcon(id: Int64, icon: String?) {
        if let icon, !icon.isEmpty {
            runWrite("UPDATE folders SET icon = ? WHERE id = ?", [.text(icon), .int(id)], context: "Folder Appearance")
        } else {
            runWrite("UPDATE folders SET icon = NULL WHERE id = ?", [.int(id)], context: "Folder Appearance")
        }
        reload()
    }

    // MARK: - برچسب‌ها

    private func setTags(bookmarkId: Int64, names: [String]) {
        runWrite("DELETE FROM bookmark_tags WHERE bookmark_id = ?", [.int(bookmarkId)], context: "Update Tags")
        for raw in names {
            let n = raw.trimmed
            guard !n.isEmpty else { continue }
            do {
                var finalId = (try db.scalarInt("SELECT id FROM tags WHERE name = ? COLLATE NOCASE", [.text(n)])) ?? 0
                if finalId == 0 {
                    finalId = try db.run("INSERT INTO tags(name) VALUES (?)", [.text(n)])
                }
                guard finalId > 0 else { continue }
                try db.run("INSERT OR IGNORE INTO bookmark_tags(bookmark_id, tag_id) VALUES (?, ?)", [
                    .int(bookmarkId), .int(finalId)
                ])
            } catch { continue }
        }
    }

    func addTag(bookmarkId: Int64, name: String) {
        let n = name.trimmed
        guard !n.isEmpty else { return }
        var current = bookmark(id: bookmarkId)?.tags ?? []
        guard !current.contains(where: { $0.lowercased() == n.lowercased() }) else { return }
        current.append(n)
        setTags(bookmarkId: bookmarkId, names: current)
        reload()
    }

    func removeTag(bookmarkId: Int64, name: String) {
        guard let row = try? db.rows("SELECT id FROM tags WHERE name = ? COLLATE NOCASE", [.text(name)]).first,
              let tid = row.int("id") else { return }
        runWrite("DELETE FROM bookmark_tags WHERE bookmark_id = ? AND tag_id = ?",
                 [.int(bookmarkId), .int(tid)], context: "Remove tag")
        reload()
    }

    // MARK: - فیلترهای ذخیره‌شده

    func refreshFilters() {
        guard let rows = try? db.rows(
            "SELECT id, name, query, scope_kind, scope_payload, sort FROM saved_filters ORDER BY name COLLATE NOCASE"
        ) else { return }
        savedFilters = rows.compactMap { r in
            guard let id = r.int("id") else { return nil }
            return SavedFilter(
                id: id,
                name: r.textOrEmpty("name"),
                query: r.textOrEmpty("query"),
                scope: Scope.from(kind: r.textOrEmpty("scope_kind"), payload: r.text("scope_payload")),
                sort: Sort(rawValue: r.textOrEmpty("sort")) ?? .newest
            )
        }
    }

    /// فیلتر فعلی (جستجو + محدوده + مرتب‌سازی) را با نام داده‌شده ذخیره می‌کند
    func saveCurrentFilter(name: String) {
        let n = name.trimmed
        guard !n.isEmpty else {
            notify(L.tr("Give the filter a name"))
            return
        }
        do {
            try db.run("""
                INSERT INTO saved_filters(name, query, scope_kind, scope_payload, sort, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, [
                    .text(n),
                    .text(query),
                    .text(scope.kind),
                    scope.payload.map { .text($0) } ?? .null,
                    .text(sort.rawValue),
                    .real(Date().timeIntervalSince1970)
                ])
            refreshFilters()
            notify(L.tr("Filter saved"))
        } catch {
            notify(L.tf("Failed to save filter: %@", error.localizedDescription))
        }
    }

    func apply(_ filter: SavedFilter) {
        query = filter.query
        sort = filter.sort
        scope = filter.scope
        notify(L.tf("Filter “%@” applied", filter.name))
    }

    func renameFilter(id: Int64, name: String) {
        let n = name.trimmed
        guard !n.isEmpty else { return }
        if runWrite("UPDATE saved_filters SET name = ? WHERE id = ?", [.text(n), .int(id)], context: "Rename Filter") {
            refreshFilters()
        }
    }

    func deleteFilter(id: Int64) {
        if runWrite("DELETE FROM saved_filters WHERE id = ?", [.int(id)], context: "Delete Filter") {
            refreshFilters()
            notify(L.tr("Filter deleted"))
        }
    }

    // MARK: - تکراری‌یاب

    /// گروه‌های تکراری بر اساس آدرس نرمال‌شده (هر گروه: جدیدترین اول)
    func duplicateGroups() -> [[Bookmark]] {
        guard let rows = try? db.rows(
            "SELECT \(Self.cols) FROM bookmarks b WHERE b.deleted_at IS NULL"
        ) else { return [] }
        var map: [String: [Bookmark]] = [:]
        for row in rows {
            let b = Bookmark(row: row)
            let key = (URLNormalizer.url(b.url)?.absoluteString ?? b.url).lowercased()
            map[key, default: []].append(b)
        }
        return map.values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.createdAt > $1.createdAt } }
            .sorted { ($0.first?.domain ?? "") < ($1.first?.domain ?? "") }
    }

    /// حذف نسخه‌های تکراری (نسخهٔ جدیدتر نگه داشته می‌شود؛ بقیه به زباله‌دان)
    func removeDuplicates() -> Int {
        let groups = duplicateGroups()
        let ids = groups.flatMap { $0.dropFirst().map(\.id) }
        guard !ids.isEmpty else { return 0 }
        delete(ids: ids)
        return ids.count
    }

    // MARK: - نسخهٔ کامل صفحه و عکس صفحه

    /// متن ذخیره‌شدهٔ یک نشانک (از پایگاه، نه از حافظه)
    /// برای جستجوی تمام‌متن، زمینهٔ دستیار و پیش‌نمایهٔ نقشهٔ ذهنی
    func savedContent(id: Int64) -> String? {
        guard let row = try? db.rows("SELECT content FROM bookmarks WHERE id = ?", [.int(id)]).first else { return nil }
        guard let text = row.text("content"), !text.isBlank else { return nil }
        return text
    }

    /// گرفتن عکس واقعی صفحه (در پس‌زمینه)
    func captureScreenshot(id: Int64) async {
        guard let b = bookmark(id: id), let url = URL(string: b.url), b.isWebPage else { return }
        guard let path = await Screenshotter.capture(url, key: b.url) else { return }
        _ = try? db.run("UPDATE bookmarks SET screenshot = ? WHERE id = ?", [.text(path), .int(id)])
        reload()
    }

    // MARK: - جستجوی سریع (نوار منو)

    func quickResults(_ q: String) -> [Bookmark] {
        let term = q.trimmed
        var sql = """
        SELECT \(Self.cols)
        FROM bookmarks b WHERE b.is_archived = 0 AND b.deleted_at IS NULL
        """
        var params: [SQLValue] = []
        if !term.isEmpty {
            let like = "%\(term)%"
            sql += " AND (b.title LIKE ? OR b.url LIKE ? OR b.domain LIKE ? OR b.note LIKE ?)"
            params.append(contentsOf: [.text(like), .text(like), .text(like), .text(like)])
            sql += " ORDER BY b.starred DESC, b.created_at DESC"
            sql += " LIMIT 10"
        } else {
            sql += " ORDER BY b.created_at DESC"
            sql += " LIMIT 40"
        }
        guard let rows = try? db.rows(sql, params) else { return [] }
        return rows.map(Bookmark.init(row:))
    }

    func bookmark(id: Int64) -> Bookmark? {
        if let hit = results.first(where: { $0.id == id }) { return hit }
        guard let row = try? db.rows("""
            SELECT \(Self.cols)
            FROM bookmarks b WHERE b.id = ?
            """, [.int(id)]).first else { return nil }
        var b = Bookmark(row: row)
        if let pairs = try? db.rows("""
            SELECT t.name AS name FROM bookmark_tags bt
            JOIN tags t ON t.id = bt.tag_id WHERE bt.bookmark_id = ? ORDER BY t.name
            """, [.int(id)]) {
            b.tags = pairs.compactMap { $0.text("name") }
        }
        return b
    }

    // MARK: - ایندکس FTS

    private func indexFTS(_ b: Bookmark) {
        guard ftsEnabled else { return }
        let content = savedContent(id: b.id) ?? ""
        _ = try? db.run("DELETE FROM fts WHERE rowid = ?", [.int(b.id)])
        _ = try? db.run("INSERT INTO fts(rowid, title, note, url, domain, content) VALUES (?, ?, ?, ?, ?, ?)", [
            .int(b.id), .text(b.title), .text(b.note), .text(b.url), .text(b.domain), .text(content)
        ])
    }

    private func removeFromFTS(_ id: Int64) {
        guard ftsEnabled else { return }
        _ = try? db.run("DELETE FROM fts WHERE rowid = ?", [.int(id)])
    }

    // MARK: - باز کردن / کپی

    func open(_ b: Bookmark) {
        guard let u = URL(string: b.url) else { return }
        NSWorkspace.shared.open(u)
        if !b.isRead { setRead(b.id, true) }
        if b.isDead { Task { await recheck(id: b.id) } }
    }

    func copyURL(_ b: Bookmark) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(b.url, forType: .string)
        notify(L.tr("URL copied"))
    }

    // MARK: - ورودی/خروجی

    func importHTML(from fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL) else {
            notify(L.tr("Could not read file"))
            return
        }
        let html = String(data: data, encoding: .utf8) ?? (String(data: data, encoding: .isoLatin1) ?? "")
        let entries = NetscapeHTML.parse(html)
        guard !entries.isEmpty else {
            notify(L.tr("No bookmarks found in file"))
            return
        }

        busy = true
        defer { busy = false }

        var added = 0
        for e in entries {
            guard let u = URLNormalizer.url(e.url) else { continue }
            let exists = (try? db.scalarInt("SELECT id FROM bookmarks WHERE url = ?", [.text(u.absoluteString)])) ?? nil
            if exists != nil { continue }

            var folderId: Int64?
            if let folderName = e.folder, !folderName.isBlank {
                folderId = folderIdByName(folderName)
                if folderId == nil {
                    folderId = try? db.run("INSERT INTO folders(name, parent_id, pos) VALUES (?, NULL, ?)", [
                        .text(folderName), .int(Int64(folders.count + added))
                    ])
                }
            }

            let now = Date().timeIntervalSince1970
            do {
                let id = try db.run("""
                    INSERT INTO bookmarks(url, title, note, domain, folder_id, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, [
                        .text(u.absoluteString),
                        .text(e.title.isBlank ? URLNormalizer.domain(u) : e.title),
                        .text(e.note ?? ""),
                        .text(URLNormalizer.domain(u)),
                        folderId.map { .int($0) } ?? .null,
                        .real(now),
                        .real(now)
                    ])
                if let b = bookmark(id: id) { indexFTS(b) }
                added += 1
            } catch { continue }
        }

        reload()
        notify(L.tf("%@ bookmarks imported", Digits.fa(added)))
    }

    private func folderIdByName(_ name: String) -> Int64? {
        let flat = flattenFolders(folders)
        return flat.first { $0.name == name }?.id
    }

    func flattenFolders(_ list: [Folder]) -> [Folder] {
        var out: [Folder] = []
        func walk(_ items: [Folder]) {
            for f in items {
                out.append(f)
                walk(f.children)
            }
        }
        walk(list)
        return out
    }

    func exportHTML(to fileURL: URL) {
        let flat = flattenFolders(folders)
        var rows: [(folder: String?, title: String, url: String, note: String)] = []
        let all = (try? db.rows("""
            SELECT b.title, b.url, b.note, b.folder_id, f.name AS folder_name
            FROM bookmarks b LEFT JOIN folders f ON f.id = b.folder_id
            WHERE b.deleted_at IS NULL
            ORDER BY f.name, b.created_at DESC
            """)) ?? []
        for r in all {
            rows.append((
                folder: r.text("folder_name"),
                title: r.textOrEmpty("title"),
                url: r.textOrEmpty("url"),
                note: r.textOrEmpty("note")
            ))
        }
        _ = flat
        let html = NetscapeHTML.render(entries: rows)
        do {
            try html.write(to: fileURL, atomically: true, encoding: .utf8)
            notify(L.tr("HTML backup saved"))
        } catch {
            notify(L.tf("Export failed: %@", error.localizedDescription))
        }
    }

    // MARK: - بررسی سلامت لینک‌ها

    func checkAllLinks() async {
        guard !isChecking else { return }
        guard let rows = try? db.rows(
            "SELECT id, url FROM bookmarks WHERE is_archived = 0 AND deleted_at IS NULL"
        ) else { return }
        let items: [(Int64, String)] = rows.compactMap { r in
            guard let id = r.int("id"), let u = r.text("url") else { return nil }
            return (id, u)
        }
        guard !items.isEmpty else {
            notify(L.tr("No bookmarks to check"))
            return
        }

        isChecking = true
        checkProgress = 0
        defer {
            isChecking = false
            checkProgress = 0
        }

        var done = 0
        let now = Date().timeIntervalSince1970
        for chunk in items.chunked(size: 6) {
            let outcomes = await withTaskGroup(of: (Int64, LinkChecker.Health).self) { group -> [(Int64, LinkChecker.Health)] in
                for (id, u) in chunk {
                    group.addTask {
                        let h = await LinkChecker.check(u)
                        return (id, h)
                    }
                }
                var collected: [(Int64, LinkChecker.Health)] = []
                for await item in group { collected.append(item) }
                return collected
            }
            for (id, health) in outcomes {
                switch health {
                case .alive:
                    _ = try? db.run("UPDATE bookmarks SET is_dead = 0, checked_at = ? WHERE id = ?", [.real(now), .int(id)])
                case .dead:
                    _ = try? db.run("UPDATE bookmarks SET is_dead = 1, checked_at = ? WHERE id = ?", [.real(now), .int(id)])
                case .unknown:
                    _ = try? db.run("UPDATE bookmarks SET checked_at = ? WHERE id = ?", [.real(now), .int(id)])
                }
            }
            done += chunk.count
            checkProgress = Double(done) / Double(items.count)
            reload()
        }

        let checkedAt = Date()
        lastCheck = checkedAt
        UserDefaults.standard.set(checkedAt.timeIntervalSince1970, forKey: "lastCheck")
        reload()
        notify(L.tr("Link check finished"))
    }

    func recheck(id: Int64) async {
        guard let b = bookmark(id: id) else { return }
        let health = await LinkChecker.check(b.url)
        let now = Date().timeIntervalSince1970
        switch health {
        case .alive:
            _ = try? db.run("UPDATE bookmarks SET is_dead = 0, checked_at = ? WHERE id = ?", [.real(now), .int(id)])
        case .dead:
            _ = try? db.run("UPDATE bookmarks SET is_dead = 1, checked_at = ? WHERE id = ?", [.real(now), .int(id)])
        case .unknown:
            break
        }
        reload()
    }

    func deleteDead() {
        let ids = (try? db.rows("SELECT id FROM bookmarks WHERE is_dead = 1"))?.compactMap { $0.int("id") } ?? []
        delete(ids: ids)
    }

    // MARK: - کمک‌کننده‌های هوش مصنوعی و «حافظه»

    /// چسباندن برچسب‌ها به اقلامِ نتیجهٔ کوئری‌های اختصاصی
    private func attachTags(_ items: inout [Bookmark]) {
        guard !items.isEmpty else { return }
        let pairs = (try? db.rows("""
            SELECT bt.bookmark_id AS bid, t.name AS name
            FROM bookmark_tags bt JOIN tags t ON t.id = bt.tag_id
            """)) ?? []
        var tagMap: [Int64: [String]] = [:]
        for p in pairs {
            if let bid = p.int("bid"), let name = p.text("name") {
                tagMap[bid, default: []].append(name)
            }
        }
        for i in items.indices { items[i].tags = tagMap[items[i].id] ?? [] }
    }

    private func fetch(_ sql: String, _ params: [SQLValue]) -> [Bookmark] {
        var items = ((try? db.rows(sql, params)) ?? []).map(Bookmark.init(row:))
        attachTags(&items)
        return items
    }

    /// نشانک‌ها با ترتیب دلخواه شناسه‌ها
    func bookmarks(ids: [Int64]) -> [Bookmark] {
        guard !ids.isEmpty else { return [] }
        let list = ids.map(String.init).joined(separator: ",")
        let items = fetch("SELECT \(Self.cols) FROM bookmarks b WHERE b.id IN (\(list))", [])
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        return items.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    func recentBookmarks(limit: Int = 40) -> [Bookmark] {
        fetch("""
            SELECT \(Self.cols) FROM bookmarks b
            WHERE b.deleted_at IS NULL
            ORDER BY b.created_at DESC LIMIT ?
            """, [.int(Int64(limit))])
    }

    /// نشانک‌های مرتبط با پرسش کاربر — پایهٔ «پرسش از کل کتابخانه»
    /// (اگر FTS فعال باشد از ایندکس کامل متن استفاده می‌کند)
    func contextBookmarks(for query: String, limit: Int = 8) -> [Bookmark] {
        let words = query
            .split(whereSeparator: { $0.isWhitespace || "،,؟?؛;:!.".contains($0) })
            .map(String.init)
            .filter { $0.count >= 3 }
        guard !words.isEmpty else { return Array(results.prefix(limit)) }

        if ftsEnabled {
            let tokens = words
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: " OR ")
            let found = fetch("""
                SELECT \(Self.cols) FROM bookmarks b
                WHERE b.deleted_at IS NULL
                  AND b.id IN (SELECT rowid FROM fts WHERE fts MATCH ?)
                ORDER BY b.starred DESC, b.updated_at DESC LIMIT ?
                """, [.text(tokens), .int(Int64(limit))])
            if found.count >= 2 { return found }
        }

        var sql = "SELECT \(Self.cols) FROM bookmarks b WHERE b.deleted_at IS NULL AND ("
        var params: [SQLValue] = []
        for (i, w) in words.prefix(5).enumerated() {
            if i > 0 { sql += " OR " }
            sql += "(b.title LIKE ? OR b.note LIKE ? OR b.url LIKE ? OR b.domain LIKE ?)"
            let like = "%\(w)%"
            params += [.text(like), .text(like), .text(like), .text(like)]
        }
        sql += ") ORDER BY b.starred DESC, b.updated_at DESC LIMIT ?"
        params.append(.int(Int64(limit)))
        let items = fetch(sql, params)
        return items.isEmpty ? Array(results.prefix(limit)) : items
    }

    /// «امروز بخوان»: نخوانده‌های قدیمی‌تر از ۷ روز
    func todayPicks(limit: Int = 5) -> [Bookmark] {
        let cutoff = Date().timeIntervalSince1970 - 7 * 86_400
        return fetch("""
            SELECT \(Self.cols) FROM bookmarks b
            WHERE b.deleted_at IS NULL AND b.is_archived = 0 AND b.is_read = 0 AND b.created_at < ?
            ORDER BY b.starred DESC, b.created_at ASC LIMIT ?
            """, [.real(cutoff), .int(Int64(limit))])
    }

    /// «دوباره ببین»: نشانک‌هایی که مدت‌هاست خوانده نشده‌اند
    func forgotten(days: Int = 60, limit: Int = 8) -> [Bookmark] {
        let cutoff = Date().timeIntervalSince1970 - Double(days) * 86_400
        return fetch("""
            SELECT \(Self.cols) FROM bookmarks b
            WHERE b.deleted_at IS NULL AND b.is_archived = 0 AND b.is_read = 0 AND b.created_at < ?
            ORDER BY b.created_at ASC LIMIT ?
            """, [.real(cutoff), .int(Int64(limit))])
    }

    /// تازه‌های امروز
    func addedToday(limit: Int = 8) -> [Bookmark] {
        let start = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        return fetch("""
            SELECT \(Self.cols) FROM bookmarks b
            WHERE b.deleted_at IS NULL AND b.created_at >= ?
            ORDER BY b.created_at DESC LIMIT ?
            """, [.real(start), .int(Int64(limit))])
    }
}
