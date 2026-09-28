import Foundation

// MARK: - ورودی/خروجی HTML مرورگرها (فرمت Netscape)

struct HTMLEntry: Sendable {
    var folder: String?
    var title: String
    var url: String
    var note: String?
}

enum NetscapeHTML {
    // MARK: خواندن

    static func parse(_ html: String) -> [HTMLEntry] {
        var out: [HTMLEntry] = []
        var currentFolder: String?

        let anchorRe = try? NSRegularExpression(
            pattern: "<a\\s+[^>]*href\\s*=\\s*(?:\"([^\"]+)\"|'([^']+)')[^>]*>(.*?)</a>",
            options: [.caseInsensitive]
        )
        let folderRe = try? NSRegularExpression(
            pattern: "<h3[^>]*>(.*?)</h3>",
            options: [.caseInsensitive]
        )

        for rawLine in html.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()

            // عنوان پوشه
            if let g = groups(folderRe, line), let name = g.first, !name.isBlank {
                currentFolder = HTMLCodec.unescape(name).trimmed
                continue
            }

            // پایان پوشه
            if upper.hasPrefix("</DL>") {
                currentFolder = nil
                continue
            }

            // نشانک
            if let g = groups(anchorRe, line) {
                // href ممکن است در گروه ۱ (دوقلقلی) یا گروه ۲ (تک‌نقلی) باشد
                let href = (g.count > 0 ? g[0] : "").isEmpty ? (g.count > 1 ? g[1] : "") : g[0]
                let title = HTMLCodec.unescape(g.count > 2 ? g[2] : "").trimmed
                guard !href.isBlank else { continue }
                out.append(HTMLEntry(folder: currentFolder, title: title, url: href.trimmed, note: nil))
                continue
            }

            // توضیح (<DD>) برای آخرین نشانک
            if line.lowercased().hasPrefix("<dd>") {
                let note = HTMLCodec.unescape(String(line.dropFirst(4))).trimmed
                if !note.isBlank, !out.isEmpty {
                    out[out.count - 1].note = note
                }
            }
        }

        return out
    }

    /// گروه‌های ۱ تا n یک regex (بدون گروه صفر)
    private static func groups(_ re: NSRegularExpression?, _ s: String) -> [String]? {
        guard let re else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range) else { return nil }
        var out: [String] = []
        for i in 1..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: s) else {
                out.append("")
                continue
            }
            out.append(String(s[r]))
        }
        return out
    }

    // MARK: نوشتن

    static func render(entries: [(folder: String?, title: String, url: String, note: String)]) -> String {
        var out = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- This is an automatically generated file.
             It will be read and overwritten.
             DO NOT EDIT! -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>\(L.tr("Bookmarks"))</TITLE>
        <H1>\(L.tr("My Bookmarks"))</H1>
        <DL><p>
        """

        let grouped = Dictionary(grouping: entries) { $0.folder ?? "├" }

        // اول «بدون پوشه»، بعد پوشه‌ها به ترتیب حروفی
        let keys = grouped.keys.sorted { a, b in
            if a == "├" { return true }
            if b == "├" { return false }
            return a < b
        }
        for key in keys {
            let items = grouped[key] ?? []
            if key == "├" {
                for e in items { out += line(for: e) }
                continue
            }
            out += "\n    <DT><H3>\(HTMLCodec.escape(key))</H3>\n    <DL><p>\n"
            for e in items { out += line(for: e, indent: 8) }
            out += "    </DL><p>\n"
        }

        out += "\n</DL><p>\n"
        return out
    }

    private static func line(for e: (folder: String?, title: String, url: String, note: String), indent: Int = 4) -> String {
        let pad = String(repeating: " ", count: indent)
        let title = e.title.isBlank ? e.url : e.title
        var s = "\n\(pad)<DT><A HREF=\"\(HTMLCodec.escape(e.url))\">\(HTMLCodec.escape(title))</A>"
        if !e.note.isBlank {
            s += "\n\(pad)<DD>\(HTMLCodec.escape(e.note))"
        }
        return s
    }
}
