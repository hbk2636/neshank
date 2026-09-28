import Foundation

// MARK: - لایهٔ هوش تحلیلی (پرسش از کتابخانه و گفتگو با دستیار)

/// پرامپت‌ها — جدا از لایهٔ شبکه تا تست‌پذیر باشند.
enum AIAdvisor {

    // MARK: اقلام زمینه

    struct ContextItem: Equatable {
        var id: Int64
        var title: String
        var domain: String
        var url: String
        var tags: [String]
        var note: String
        var excerpt: String?

        init(bookmark: Bookmark, excerpt: String? = nil) {
            id = bookmark.id
            title = bookmark.displayTitle
            domain = bookmark.domain
            url = bookmark.url
            tags = bookmark.tags
            note = bookmark.note
            self.excerpt = excerpt
        }
    }

    static func itemsPrompt(_ items: [ContextItem], excerptLimit: Int = 220) -> String {
        guard !items.isEmpty else { return "فهرست خالی است." }
        var out = "نشانک‌ها:\n"
        for item in items {
            var line = "\(item.id) | \(item.title) | \(item.domain.isEmpty ? "—" : item.domain)"
            if !item.tags.isEmpty { line += " | برچسب: \(item.tags.joined(separator: "، "))" }
            if !item.note.isBlank { line += " | یادداشت: \(AIClient.clip(item.note, 90))" }
            if let ex = item.excerpt, !ex.isBlank { line += " | متن: \(AIClient.clip(ex, excerptLimit))" }
            out += line + "\n"
        }
        return out
    }

    // MARK: پرامپت پرسش از کتابخانه

    static func librarySystemPrompt(profile: String?) -> String {
        var lines = """
        تو دستیار «نشانک» هستی و فقط بر پایهٔ نشانک‌های کتابخانهٔ کاربر پاسخ می‌دهی.

        قواعد:
        ۱) پاسخ به زبان \(AppLanguage.current.promptLanguageName) باشد؛ کوتاه و روان؛ اول یک خط جمع‌بندی، بعد جزئیات.
        ۲) هر جا از یک منبع استفاده کردی، شمارهٔ آن را با [۱]، [۲] … بنویس.
        ۳) اگر پاسخ در نشانک‌ها نبود، صریح بگو «در کتابخانه‌ات چیزی دربارهٔ این نیست» و بگو چه چیزی را ذخیره کند.
        ۴) اطلاعات ناقص را حدس نزن؛ اگر متنی نداری بگو.
        ۵) در پایان، اگر مفید است، ۱ تا ۲ پیشنهاد عملی بده.
        """
        if let profile, !profile.isBlank {
            lines += "\n\nپروفایل کاربر:\n\(AIClient.clip(profile, 900))"
        }
        return lines
    }

    static func libraryUserPrompt(question: String, items: [ContextItem]) -> String {
        var out = "منابع موجود در کتابخانه (شماره‌ها همان ارجاع پاسخ هستند):\n"
        if items.isEmpty {
            out += "(هیچ نشانک مرتبطی پیدا نشد)\n"
        }
        for (i, item) in items.enumerated() {
            out += """
            [\(i + 1)] \(item.title) — \(item.domain.isEmpty ? "—" : item.domain)
            """
            if !item.tags.isEmpty { out += "\n    برچسب‌ها: \(item.tags.joined(separator: "، "))" }
            if !item.note.isBlank { out += "\n    یادداشت کاربر: \(AIClient.clip(item.note, 160))" }
            if let ex = item.excerpt, !ex.isBlank { out += "\n    متن: \(AIClient.clip(ex, 700))" }
            out += "\n"
        }
        out += "\nپرسش کاربر: \(question.trimmed)"
        return out
    }

    static func citations(_ items: [ContextItem]) -> [ChatMessage.Citation] {
        items.map { ChatMessage.Citation(bookmarkId: $0.id, title: $0.title) }
    }
}
