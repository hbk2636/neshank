import Foundation

// MARK: - چت

struct Chat: Identifiable, Equatable {
    enum Kind: String {
        case bookmark   // چت دربارهٔ یک نشانک
        case library    // پرسش از کل کتابخانه

        var label: String {
            switch self {
            case .bookmark: return L.tr("Bookmark")
            case .library: return L.tr("Library")
            }
        }

        var icon: String {
            switch self {
            case .bookmark: return "bookmark"
            case .library: return "books.vertical"
            }
        }
    }

    var id: Int64
    var title: String
    var kind: Kind
    var bookmarkId: Int64?
    var pinned: Bool
    var createdAt: Date
    var updatedAt: Date
    var messageCount: Int = 0
    var preview: String = ""
    var bookmarkTitle: String?
}

// MARK: - پیام چت

struct ChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user, assistant

        var label: String {
            self == .user ? L.tr("Me") : L.tr("Assistant")
        }
    }

    struct Citation: Codable, Equatable, Identifiable, Hashable {
        var bookmarkId: Int64
        var title: String
        var id: Int64 { bookmarkId }
    }

    var id: Int64
    var chatId: Int64
    var role: Role
    var content: String
    var citations: [Citation]
    var createdAt: Date
}

// MARK: - لاگ تصمیم

struct Decision: Identifiable, Equatable {
    enum Verdict: String, CaseIterable, Identifiable {
        case buy, skip, wait, note

        var id: String { rawValue }

        var label: String {
            switch self {
            case .buy: return L.tr("Buy")
            case .skip: return L.tr("Don't Buy")
            case .wait: return L.tr("Not Now")
            case .note: return L.tr("Note")
            }
        }

        var icon: String {
            switch self {
            case .buy: return "cart.fill.badge.plus"
            case .skip: return "xmark.circle"
            case .wait: return "clock.arrow.circlepath"
            case .note: return "note.text"
            }
        }
    }

    var id: Int64
    var bookmarkId: Int64
    var verdict: Verdict
    var note: String
    var createdAt: Date
}

// MARK: - کمک‌کننده‌های متنی

enum ChatText {
    /// تک‌خطی‌کردن و کوتاه‌کردن متن برای پیش‌نمایش فهرست
    static func clean(_ text: String?, limit: Int = 90) -> String {
        guard let text, !text.isBlank else { return "" }
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmed
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)) + "…"
    }

    /// عنوان خودکار چت از نخستین پرسش کاربر
    static func autoTitle(_ text: String, limit: Int = 42) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmed
        guard !flat.isEmpty else { return L.tr("New Library Chat") }
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)) + "…"
    }
}
