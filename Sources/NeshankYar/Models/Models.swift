import Foundation
import AppKit
import SwiftUI

// MARK: - نشانک

struct Bookmark: Identifiable, Hashable {
    var id: Int64
    var url: String
    var title: String
    var note: String
    var domain: String
    var folderId: Int64?
    var tags: [String]
    var starred: Bool
    var isRead: Bool
    var isArchived: Bool
    var isDead: Bool
    var favicon: String?
    var thumb: String?
    /// عکس واقعی صفحه (اگر گرفته شده باشد)
    var screenshot: String?
    /// تاریخ رفتن به زباله‌دان (nil = فعال)
    var deletedAt: Date?
    /// متن کامل صفحه (فقط هنگام نیاز بارگذاری می‌شود)
    var content: String?
    var createdAt: Date
    var updatedAt: Date
    var checkedAt: Date?

    init(row: DBRow) {
        id = row.int("id") ?? 0
        url = row.textOrEmpty("url")
        title = row.textOrEmpty("title")
        note = row.textOrEmpty("note")
        domain = row.textOrEmpty("domain")
        folderId = row.int("folder_id")
        tags = []
        starred = row.bool("starred")
        isRead = row.bool("is_read")
        isArchived = row.bool("is_archived")
        isDead = row.bool("is_dead")
        favicon = row.text("favicon")
        thumb = row.text("thumb")
        screenshot = row.text("screenshot")
        deletedAt = row.double("deleted_at").map { Date(timeIntervalSince1970: $0) }
        content = row.text("content")
        createdAt = Date(timeIntervalSince1970: row.double("created_at") ?? 0)
        updatedAt = Date(timeIntervalSince1970: row.double("updated_at") ?? 0)
        checkedAt = row.double("checked_at").map { Date(timeIntervalSince1970: $0) }
    }

    var isTrashed: Bool { deletedAt != nil }

    /// تصویر شاخص (عکس صفحه ← تصویر معرفی ← فاوآیکون)
    var heroImage: String? { screenshot ?? thumb }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? url : t
    }

    var isWebPage: Bool {
        url.hasPrefix("http://") || url.hasPrefix("https://")
    }
}

// MARK: - پوشه

struct Folder: Identifiable, Hashable {
    var id: Int64
    var name: String
    var parentId: Int64?
    /// رنگ سفارشی (HEX)
    var color: String?
    /// آیکون سفارشی (SF Symbols)
    var icon: String?
    /// سنجاق‌شده به بالای فهرست پوشه‌ها
    var pinned: Bool = false
    var children: [Folder] = []

    /// رنگ نمایشی (پیش‌فرض: زردِ پوشه)
    var uiColor: Color { color.map(Color.init(hex:)) ?? .yellow }

    var uiIcon: String {
        if let icon, !icon.isEmpty { return icon }
        return children.isEmpty ? "folder" : "folder.fill"
    }
}

// پوشهٔ تخت برای Picker ها
struct FolderOption: Identifiable, Hashable {
    var id: Int64
    var label: String
    var depth: Int
}

extension Folder {
    /// برای OutlineGroup (نیازمند کلیدپاث اختیاری)
    var outlineChildren: [Folder]? { children }
}

// MARK: - برچسب

struct TagCount: Identifiable, Hashable {
    var id: Int64
    var name: String
    var count: Int
}

// MARK: - شمارنده‌ها

struct Counts: Hashable {
    var all = 0
    var starred = 0
    var unread = 0
    var dead = 0
    var archived = 0
    var trash = 0
}

// MARK: - مقصدهای ویرایشگر

enum EditorTarget: Identifiable {
    case new(folderId: Int64?)
    case edit(Bookmark)

    var id: String {
        switch self {
        case .new(let f): return "new:\(f.map(String.init) ?? "-")"
        case .edit(let b): return "edit:\(b.id)"
        }
    }

    var bookmark: Bookmark? {
        if case .edit(let b) = self { return b }
        return nil
    }
}

// MARK: - نرمال‌سازی آدرس

enum URLNormalizer {
    private static let trackers: Set<String> = [
        "fbclid", "gclid", "yclid", "igshid", "mc_cid", "mc_eid",
        "ref", "ref_src", "s", "cmpid", "spm", "from", "source"
    ]

    /// آدرس خام را به URL معتبرِ تمیز تبدیل می‌کند (پارامترهای ردیابی حذف می‌شوند).
    static func url(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\n", with: "")
        s = s.replacingOccurrences(of: "\"", with: "")
        guard !s.isEmpty else { return nil }

        if s.lowercased().hasPrefix("mailto:") || s.lowercased().hasPrefix("tel:") {
            return URL(string: s)
        }

        if !s.contains("://") {
            if s.hasPrefix("//") { s = "https:" + s } else { s = "https://" + s }
        }

        guard var comps = URLComponents(string: s), let host = comps.host, !host.isEmpty else { return nil }

        if let items = comps.queryItems, !items.isEmpty {
            let kept = items.filter { item in
                let n = item.name.lowercased()
                if n.hasPrefix("utm_") { return false }
                if trackers.contains(n) { return false }
                return true
            }
            comps.queryItems = kept.isEmpty ? nil : kept
        }

        return comps.url
    }

    /// دامنهٔ بدون www
    static func domain(_ url: URL) -> String {
        guard let host = url.host else { return "" }
        let h = host.lowercased()
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    static func domain(ofString s: String) -> String {
        guard let u = url(s) else { return "" }
        return domain(u)
    }
}

// MARK: - اعداد و تاریخ فارسی

enum Digits {
    static let persian: [Character] = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]

    static func fa<T: BinaryInteger>(_ n: T) -> String { fa(String(n)) }

    /// ارقام فارسی فقط برای زبان فارسی؛ بقیهٔ زبان‌ها لاتین
    static func fa(_ s: String) -> String {
        guard AppLanguage.current == .persian else { return s }
        return String(s.map { ch in
            if ch.isASCII, ch.isNumber, let v = ch.wholeNumberValue, v < 10 { return persian[v] }
            return ch
        })
    }
}

private final class FormatterBox: @unchecked Sendable {
    let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fa_IR")
        f.unitsStyle = .full
        return f
    }()

    let relativeEn: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .full
        return f
    }()

    let persianDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .persian)
        f.locale = Locale(identifier: "fa_IR")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    let gregorianDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateStyle = .medium
        return f
    }()

    let time: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .persian)
        f.locale = Locale(identifier: "fa_IR")
        f.dateFormat = "HH:mm"
        return f
    }()

    let gregorianMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM yyyy"
        return f
    }()

    let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .persian)
        f.locale = Locale(identifier: "fa_IR")
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}

enum Dates {
    private static let box = FormatterBox()

    static func relative(_ d: Date) -> String {
        if AppLanguage.current == .persian { return box.relative.localizedString(for: d, relativeTo: Date()) }
        return box.relativeEn.localizedString(for: d, relativeTo: Date())
    }

    static func persian(_ d: Date) -> String {
        if AppLanguage.current == .persian { return box.persianDate.string(from: d) }
        return box.gregorianDate.string(from: d)
    }

    static func persianDateTime(_ d: Date) -> String {
        "\(persian(d)) — \(box.time.string(from: d))"
    }

    /// «مهر ۱۴۰۴» / «Oct 2025» — برای گروه‌بندی فهرست بر اساس ماه
    static func persianMonth(_ d: Date) -> String {
        if AppLanguage.current == .persian { return box.monthYear.string(from: d) }
        return box.gregorianMonth.string(from: d)
    }
}

// MARK: - ابزارهای عمومی

enum AppPaths {
    static let root: URL = {
        #if DEBUG
        // Isolated app-level integration tests can set this environment variable.
        // Release builds ignore it and always use the normal Application Support directory.
        if let testPath = ProcessInfo.processInfo.environment["NESHANKYAR_TEST_DATA_DIR"],
           !testPath.trimmed.isEmpty {
            let testRoot = URL(fileURLWithPath: testPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
            return testRoot
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("NeshankYar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var dbPath: String { root.appendingPathComponent("NeshankYar.sqlite3").path }

    /// پوشهٔ بک‌آپ‌های خودکار/دستی دیتابیس (چند صد کیلوبایت برای هر نسخه)
    static var backupsDir: URL {
        let dir = root.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// فایل کش‌شده (فاوآیکون/تصویر) را ذخیره و مسیرش را برمی‌گرداند.
    @discardableResult
    static func save(_ data: Data, folder: String, key: String, ext: String) -> String? {
        guard !data.isEmpty else { return nil }
        let dir = root.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cleanExt = ext.isEmpty ? "png" : ext
        let url = dir.appendingPathComponent("\(fnv1a(key)).\(cleanExt)")
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    @MainActor
    static func revealInFinder() {
        NSApp.activate(ignoringOtherApps: true)
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }
}

func fnv1a(_ s: String) -> String {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 {
        h ^= UInt64(b)
        h &*= 0x100_0000_01b3
    }
    return String(format: "%016llx", h)
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var isBlank: Bool { trimmed.isEmpty }
}

extension Array {
    /// تقسیم آرایه به بلوک‌های کوچک‌تر
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var out: [[Element]] = []
        var idx = startIndex
        while idx < endIndex {
            let next = self.index(idx, offsetBy: size, limitedBy: endIndex) ?? endIndex
            out.append(Array(self[idx..<next]))
            idx = next
        }
        return out
    }
}
