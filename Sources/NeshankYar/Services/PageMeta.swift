import Foundation

// MARK: - اطلاعات صفحه

struct PageMetaResult: Sendable {
    var title: String?
    var description: String?
    var faviconURL: URL?
    var imageURL: URL?
    /// متن کامل صفحه (برای جستجوی عمیق و زمینهٔ دستیار)
    var content: String?
}

// MARK: - دریافت اطلاعات صفحه

enum PageMeta {
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    static func fetch(_ url: URL) async -> PageMetaResult {
        var meta = PageMetaResult()
        meta.faviconURL = URL(string: "https://\(URLNormalizer.domain(url))/favicon.ico")

        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<400).contains(http.statusCode),
              let html = decode(data, encodingName: http.textEncodingName)
        else { return meta }

        meta.title = firstGroup(pattern: "<title[^>]*>([^<]*)</title>", in: html)
            .map(HTMLCodec.unescape)
        meta.description = metaTag(key: "og:description", in: html)
            ?? metaTag(key: "description", in: html)
            .map(HTMLCodec.unescape)

        if let icon = linkIcon(in: html, base: url) {
            meta.faviconURL = icon
        }
        if let img = metaTag(key: "og:image", in: html).flatMap({ URL(string: $0, relativeTo: url)?.absoluteURL })
            ?? metaTag(key: "twitter:image", in: html).flatMap({ URL(string: $0, relativeTo: url)?.absoluteURL }) {
            meta.imageURL = img
        }
        if let t = meta.title { meta.title = HTMLCodec.unescape(t) }
        if let d = meta.description { meta.description = HTMLCodec.unescape(d) }
        meta.content = HTMLText.extractMain(from: html)
        return meta
    }

    /// دانلود فایل با سقف حجم؛ خروجی: (داده، پسوند)
    static func download(_ url: URL, maxBytes: Int = 2_000_000) async -> (Data, String)? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              !data.isEmpty, data.count <= maxBytes
        else { return nil }

        let mime = (resp as? HTTPURLResponse)?.mimeType?.lowercased() ?? ""
        if mime.contains("svg") { return nil }
        guard let ext = extensionFor(mime: mime, data: data, url: url) else { return nil }
        return (data, ext)
    }

    // MARK: کمکی‌ها

    private static func decode(_ data: Data, encodingName: String?) -> String? {
        if let name = encodingName,
           let enc = String.Encoding(ianaCharset: name),
           let s = String(data: data, encoding: enc) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func group(_ index: Int, _ result: NSTextCheckingResult, _ s: String) -> String? {
        guard index < result.numberOfRanges, let r = Range(result.range(at: index), in: s) else { return nil }
        let v = String(s[r]).trimmed
        return v.isEmpty ? nil : v
    }

    private static func firstGroup(pattern: String, in s: String) -> String? {
        guard let re = regex(pattern) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range) else { return nil }
        return group(1, m, s)
    }

    private static func metaTag(key: String, in html: String) -> String? {
        guard let re = regex("<meta\\b[^>]*>") else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        for m in re.matches(in: html, range: range) {
            guard let tagRange = Range(m.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let keyPattern = "(?:property|name)\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: key))[\"']"
            guard tag.range(of: keyPattern, options: [.regularExpression, .caseInsensitive]) != nil else { continue }
            if let value = firstGroup(pattern: "content\\s*=\\s*[\"']([^\"']*)[\"']", in: tag) {
                return HTMLCodec.unescape(value)
            }
        }
        return nil
    }

    private static func linkIcon(in html: String, base: URL) -> URL? {
        guard let re = regex("<link\\b[^>]*>") else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        var shortcut: URL?
        for m in re.matches(in: html, range: range) {
            guard let tagRange = Range(m.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard tag.range(of: "rel\\s*=\\s*[\"'][^\"']*icon[^\"']*[\"']",
                            options: [.regularExpression, .caseInsensitive]) != nil else { continue }
            guard let href = firstGroup(pattern: "href\\s*=\\s*[\"']([^\"']+)[\"']", in: tag) else { continue }
            let cleaned = HTMLCodec.unescape(href)
            guard let u = URL(string: cleaned, relativeTo: base)?.absoluteURL,
                  let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }
            let isApple = tag.range(of: "apple-touch", options: [.regularExpression, .caseInsensitive]) != nil
            if !isApple { return u }
            shortcut = u
        }
        return shortcut
    }

    private static func extensionFor(mime: String, data: Data, url: URL) -> String? {
        if mime.contains("png") { return "png" }
        if mime.contains("jpeg") || mime.contains("jpg") { return "jpg" }
        if mime.contains("gif") { return "gif" }
        if mime.contains("webp") { return "webp" }
        if mime.contains("ico") { return "ico" }
        if mime.contains("avif") { return "avif" }

        // حدس از روی بایت‌ها
        let d = data.prefix(16)
        if d.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if d.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if d.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if d.starts(with: [0x00, 0x00, 0x01, 0x00]) { return "ico" }
        if d.count >= 12, d[0..<4].elementsEqual("RIFF".utf8), d[8..<12].elementsEqual("WEBP".utf8) { return "webp" }

        let ext = url.pathExtension.lowercased()
        let allowed = ["png", "jpg", "jpeg", "gif", "webp", "ico", "avif"]
        if allowed.contains(ext) { return ext == "jpeg" ? "jpg" : ext }
        return nil
    }
}

private extension String.Encoding {
    init?(ianaCharset name: String) {
        let enc = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard enc != kCFStringEncodingInvalidId else { return nil }
        self.init(rawValue: CFStringConvertEncodingToNSStringEncoding(enc))
    }
}

// MARK: - کدگذاری/کدگشایی HTML

enum HTMLCodec {
    static func unescape(_ s: String) -> String {
        var out = s
        let pairs: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#34;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&#x27;", "'"), ("&#x2F;", "/"), ("&hellip;", "…")
        ]
        for (a, b) in pairs { out = out.replacingOccurrences(of: a, with: b) }
        // اعداد دهگی و شانزدهگی
        out = replaceNumeric(out, radix: 10, pattern: "&#(\\d{1,6});")
        out = replaceNumeric(out, radix: 16, pattern: "&#x([0-9a-fA-F]{1,6});")
        return out
    }

    private static func replaceNumeric(_ s: String, radix: Int, pattern: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        var result = s
        let matches = re.matches(in: s, range: range).reversed()
        for m in matches {
            guard let r = Range(m.range, in: s), let numRange = Range(m.range(at: 1), in: s) else { continue }
            guard let code = Int(String(s[numRange]), radix: radix), let scalar = UnicodeScalar(code) else { continue }
            result.replaceSubrange(r, with: String(Character(scalar)))
        }
        return result
    }

    static func escape(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        return out
    }
}
