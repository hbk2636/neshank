import Foundation

// MARK: - استخراج متن کامل صفحه (برای جستجوی عمیق و زمینهٔ دستیار)

enum HTMLText {
    /// حداکثر طول متن ذخیره‌شده برای هر صفحه
    static let maxChars = 180_000

    /// از HTML خام، متن خوانا و تمیز می‌سازد
    static func extract(from html: String) -> String {
        var s = html

        // ۱) حذف بلوک‌های غیرمتنی (header/button/select هم معمولاً ناوبری و کنترل‌اند، نه متن اصلی)
        for tag in ["script", "style", "noscript", "svg", "head", "nav", "header", "footer",
                    "aside", "form", "iframe", "canvas", "button", "select", "template", "dialog"] {
            s = gsub("<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", "", in: s)
        }

        // ۲) مرزبندی خطوط
        s = gsub("<br\\s*/?>", "\n", in: s)
        s = gsub("</(p|div|li|h[1-6]|tr|blockquote|section|article|pre|table)>", "\n", in: s, ignoreCase: true)
        s = gsub("<li\\b[^>]*>", "\n• ", in: s)
        s = gsub("</h[1-6]>", "\n", in: s)

        // ۳) حذف همهٔ تگ‌ها
        s = gsub("<[^>]+>", " ", in: s)

        // ۴) کدگشایی نویسه‌ها
        s = HTMLCodec.unescape(s)

        // ۵) نرمال‌سازی فاصله‌ها و خط‌ها
        s = gsub("[ \t\u{00A0}]+", " ", in: s)
        let lines = s
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var out = lines.joined(separator: "\n")

        // ۶) سقف طول
        if out.count > maxChars {
            let idx = out.index(out.startIndex, offsetBy: maxChars)
            out = String(out[..<idx])
        }
        return out.trimmed
    }

    /// محتوای اصلی صفحه را از دل ناوبری/منو/پابرگ بیرون می‌کشد.
    /// روش: اسکن بلوک‌های کانتینر، حذف بویلرپلیت بر اساس class/id، جریمهٔ تراکم لینک،
    /// و انتخاب کاندید با بیشترین متن پروژه‌وار. این فقط مسیر ایستاست؛ صفحات
    /// جاوااسکریپتی از `WebPageReader` (Readability در WKWebView) می‌آیند.
    static func extractMain(from html: String) -> String {
        let blocks = containerBlocks(in: html)
        guard !blocks.isEmpty else { return extract(from: html) }

        struct Candidate {
            let text: String
            let score: Double
            let chars: Int
            let range: Range<String.Index>
        }
        var candidates: [Candidate] = []

        for block in blocks.filter({ $0.scorable }).prefix(600) {
            if isBoilerplate(block.classHint) { continue }
            let rawLength = html.distance(from: block.range.lowerBound, to: block.range.upperBound)
            guard rawLength >= 250 else { continue }
            let raw = String(html[block.range])
            let text = extract(from: raw)
            let chars = text.count
            guard chars >= 150 else { continue }

            let linkChars = anchorTextLength(in: raw)
            let density = Double(linkChars) / Double(max(1, chars))
            guard density <= 0.65 else { continue } // کانتینر پر از لینک = ناوبری، نه متن

            let semantic = isSemantic(block)
            var score = Double(min(chars, semantic ? 9000 : 3500)) * (1.0 - density)
            score += Double(min(countOccurrences("</p>", in: raw), 60)) * 40
            score += Double(min(countOccurrences("</h[1-6]>", in: raw), 25)) * 40
            score += Double(min(commaCount(in: text), 200)) * 3
            if semantic { score *= 1.3 }
            candidates.append(Candidate(text: text, score: score, chars: chars, range: block.range))
        }

        guard var best = candidates.max(by: { $0.score < $1.score }),
              best.score >= 320, best.chars >= 200
        else {
            // هیچ کاندید قابل‌قبولی نبود: کل صفحه، ولی بعد از حذف بلوک‌های بویلرپلیت
            return extract(from: removingRanges(blocks.filter { isBoilerplate($0.classHint) }.map { $0.range },
                                                from: html[...]))
        }

        // اگر کاندید متمرکزتری درون برنده هست (مثل div محتوا درون پوستهٔ کل صفحه)
        // و امتیازش نزدیک است، همان را برگزین تا منو و پابرگِ برادرش وارد متن نشود.
        // سنجش نسبت به امتیاز برندهٔ اصلی است تا زنجیرهٔ فرود محتوا را نبرد.
        let topScore = best.score
        while let inner = candidates
            .filter({ $0.range.lowerBound > best.range.lowerBound && $0.range.upperBound < best.range.upperBound })
            .max(by: { $0.score < $1.score }),
            inner.score >= topScore * 0.65 {
            best = inner
        }

        // زیربلوک‌های بویلرپلیت داخل برنده (اطلاعیه، جعبهٔ ناوبری، پابرگ و…) را از متنش حذف کن
        let subBoiler = blocks.filter {
            isBoilerplate($0.classHint) && $0.range != best.range &&
            $0.range.lowerBound >= best.range.lowerBound && $0.range.upperBound <= best.range.upperBound
        }.map { $0.range }
        let winnerHTML = removingRanges(subBoiler, from: html[best.range])
        return extract(from: winnerHTML)
    }

    // MARK: اسکن بلوک‌های کانتینر

    private struct ContainerBlock {
        let tag: String
        /// مقادیر class و id (حروف کوچک) برای تشخیص منو/ناوبری/بویلرپلیت
        let classHint: String
        let range: Range<String.Index>
        /// کاندید امتیازدهی محتواست یا فقط برای حذف بویلرپلیت اسکن شده
        let scorable: Bool
    }

    private static let candidateTags: Set<String> = ["article", "main", "section", "div", "td"]
    /// جدول و فهرست‌ها کاندید محتوا نیستند (جدول داده یا فهرست لینک می‌مانند)
    /// ولی اگر class/id بویلرپلیت داشته باشند (ambox، navbox، catlinks و…) حذف می‌شوند.
    private static let scanOnlyTags: Set<String> = ["table", "ul", "ol"]
    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    /// نشانه‌های بویلرپلیت در class/id: منو، ناوبری، پابرگ، اشتراک، تبلیغ و…
    private static let boilerTokens = [
        "nav", "menu", "navbar", "topbar", "top-bar", "masthead", "site-header", "site-head",
        "header", "footer", "bottombar", "bottom-bar", "sidebar", "side-bar",
        "comment", "share", "sharing", "social", "related", "recommend",
        "breadcrumb", "widget", "subscribe", "newsletter", "advert", "ads",
        "promo", "popup", "modal", "cookie", "consent", "banner", "toolbar",
        "pagination", "pager", "login", "register", "signup", "skip-link",
        "post-meta", "entry-meta", "author-box", "tagcloud", "tag-cloud",
        "navbox", "catlinks", "metadata", "printfooter", "ambox", "hatnote"
    ]

    /// نشانه‌های معنایی محتوای اصلی (امتیاز مثبت)
    private static let semanticTokens = [
        "article", "entry-content", "post-content", "main-content", "article-body",
        "article-content", "post-body", "story", "blog-post", "single-post", "content"
    ]

    /// بلوک‌های کانتینر متوازن‌شده را با یک اسکن تک‌گذره برمی‌گرداند؛
    /// تگ‌های نابسته تا انتهای سند بسته فرض می‌شوند.
    private static func containerBlocks(in html: String) -> [ContainerBlock] {
        var blocks: [ContainerBlock] = []
        var stack: [(tag: String, hint: String, start: String.Index)] = []
        var i = html.startIndex
        while i < html.endIndex, let lt = html[i...].firstIndex(of: "<") {
            let after = html.index(after: lt)
            guard after < html.endIndex else { break }
            let c = html[after]
            if c == "!" {
                if html[after...].hasPrefix("!--") {
                    i = html[after...].range(of: "-->")?.upperBound ?? html.endIndex
                } else {
                    i = html[after...].firstIndex(of: ">").map { html.index(after: $0) } ?? html.endIndex
                }
                continue
            }
            if c == "?" {
                i = html[after...].range(of: "?>")?.upperBound ?? html.endIndex
                continue
            }

            var j = after
            var isClose = false
            if c == "/" {
                isClose = true
                j = html.index(after: j)
            }
            var name = ""
            while j < html.endIndex, html[j].isLetter || html[j].isNumber {
                name += html[j].lowercased()
                j = html.index(after: j)
            }
            guard !name.isEmpty, let gt = html[j...].firstIndex(of: ">") else {
                i = after
                continue
            }
            let inner = String(html[j..<gt])
            let selfClosing = inner.hasSuffix("/")

            if isClose {
                let tracked = candidateTags.union(scanOnlyTags).contains(name)
                if tracked, let idx = stack.lastIndex(where: { $0.tag == name }) {
                    let open = stack[idx]
                    blocks.append(ContainerBlock(tag: name, classHint: open.hint, range: open.start..<lt,
                                                 scorable: candidateTags.contains(name)))
                    stack.removeSubrange(idx...)
                }
            } else if candidateTags.union(scanOnlyTags).contains(name), !voidTags.contains(name), !selfClosing {
                stack.append((name, attributesHint(inner), lt))
            }
            i = html.index(after: gt)
        }
        for open in stack {
            blocks.append(ContainerBlock(tag: open.tag, classHint: open.hint,
                                         range: open.start..<html.endIndex,
                                         scorable: candidateTags.contains(open.tag)))
        }
        return blocks
    }

    // MARK: کمکی‌های امتیازدهی

    private static func attributesHint(_ tagInner: String) -> String {
        var hint = ""
        for attr in ["class", "id"] {
            if let value = attributeValue(attr, in: tagInner) {
                hint += " " + value.lowercased()
            }
        }
        return hint
    }

    private static func attributeValue(_ attr: String, in tagInner: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: "(?:^|[\\s\"'])\(attr)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))",
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(tagInner.startIndex..., in: tagInner)
        guard let m = re.firstMatch(in: tagInner, range: range) else { return nil }
        for gi in [2, 3, 4] where gi < m.numberOfRanges {
            if let r = Range(m.range(at: gi), in: tagInner) { return String(tagInner[r]) }
        }
        return nil
    }

    private static func matchesToken(_ token: String, in hint: String) -> Bool {
        hint.range(of: "(^|[^a-z0-9])\(token)([^a-z0-9]|$)",
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isBoilerplate(_ hint: String) -> Bool {
        guard !hint.isEmpty else { return false }
        return boilerTokens.contains { matchesToken($0, in: hint) }
    }

    private static func isSemantic(_ block: ContainerBlock) -> Bool {
        if block.tag == "article" || block.tag == "main" { return true }
        return semanticTokens.contains { matchesToken($0, in: block.classHint) }
    }

    /// مجموع نویسه‌های متنِ داخل لینک‌ها (برای محاسبهٔ تراکم لینک)
    private static func anchorTextLength(in html: String) -> Int {
        guard let re = try? NSRegularExpression(
            pattern: "<a\\b[^>]*>[\\s\\S]*?</a>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return 0 }
        let range = NSRange(html.startIndex..., in: html)
        var total = 0
        for m in re.matches(in: html, range: range) {
            guard let r = Range(m.range, in: html) else { continue }
            total += extract(from: String(html[r])).count
        }
        return total
    }

    private static func countOccurrences(_ pattern: String, in s: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        return re.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
    }

    private static func commaCount(in text: String) -> Int {
        text.filter { $0 == "،" || $0 == "," }.count
    }

    /// حذف مجموعه بازه از متن؛ فقط بازه‌های maximal حذف می‌شوند
    /// (تودرتوها با بزرگ‌ترینشان می‌روند) و از انتها به ابتدا بریده می‌شوند.
    /// ورودی می‌تواند Substring باشد چون ایندکس‌های والد را حفظ می‌کند.
    private static func removingRanges(_ targets: [Range<String.Index>], from s: Substring) -> String {
        guard !targets.isEmpty else { return String(s) }
        let maximal = targets.filter { r in
            !targets.contains { outer in
                outer != r && outer.lowerBound <= r.lowerBound && r.upperBound <= outer.upperBound
            }
        }
        var out = s
        for r in maximal.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            out.removeSubrange(r)
        }
        return String(out)
    }

    private static func gsub(_ pattern: String, _ template: String, in s: String, ignoreCase: Bool = false) -> String {
        guard let re = try? NSRegularExpression(
            pattern: pattern,
            options: ignoreCase ? [.caseInsensitive, .dotMatchesLineSeparators] : [.dotMatchesLineSeparators]
        ) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
    }
}
