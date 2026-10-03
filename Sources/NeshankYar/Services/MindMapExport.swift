import Foundation
import AppKit

// MARK: - تم‌های نقشهٔ ذهنی (نام‌ها با THEMES در Resources/MindMap/canvas.html یکی است)

enum MindMapTheme: String, CaseIterable, Identifiable {
    case light, dark, forest, ocean, sunset, lavender, mono, sand, sakura, mint

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return L.tr("Light")
        case .dark: return L.tr("Dark")
        case .forest: return L.tr("Forest")
        case .ocean: return L.tr("Ocean")
        case .sunset: return L.tr("Sunset")
        case .lavender: return L.tr("Lavender")
        case .mono: return L.tr("Monochrome")
        case .sand: return L.tr("Sand")
        case .sakura: return L.tr("Sakura")
        case .mint: return L.tr("Mint")
        }
    }

    var icon: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .forest: return "leaf"
        case .ocean: return "drop"
        case .sunset: return "sun.horizon.fill"
        case .lavender: return "sparkles"
        case .mono: return "circle.lefthalf.filled"
        case .sand: return "sun.dust.fill"
        case .sakura: return "camera.macro"
        case .mint: return "leaf.circle"
        }
    }

    /// تم‌های تیره — برای هماهنگی پیش‌نمایش با رنگ‌سیستم
    var isDark: Bool {
        switch self {
        case .light, .sakura, .mint: return false
        default: return true
        }
    }

    static func forColorScheme(dark: Bool) -> MindMapTheme { dark ? .dark : .light }
}

// MARK: - چیدمان‌های نقشهٔ ذهنی (نام‌ها با LAYOUT_NAMES در canvas.html یکی است)

enum MindMapLayout: String, CaseIterable, Identifiable {
    case tree, org, radial, outline, timeline, mindmap

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tree: return L.tr("Horizontal Tree")
        case .org: return L.tr("Organizational (Vertical)")
        case .radial: return L.tr("Radial")
        case .outline: return L.tr("Outline")
        case .timeline: return L.tr("Timeline (Top–Bottom)")
        case .mindmap: return L.tr("Mind Map (Two-Sided)")
        }
    }

    var icon: String {
        switch self {
        case .tree: return "arrow.triangle.branch"
        case .org: return "list.bullet.indent"
        case .radial: return "circle.hexagongrid"
        case .outline: return "text.alignleft"
        case .timeline: return "arrow.left.and.right.circle"
        case .mindmap: return "arrow.left.and.right"
        }
    }

    static func fromJSON(_ json: String) -> MindMapLayout? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meta = obj["meta"] as? [String: Any],
              let layout = meta["layout"] as? String
        else { return nil }
        return MindMapLayout(rawValue: layout)
    }
}

// MARK: - جهت چیدمان

enum MindMapDirection: Int {
    /// ریشه چپ، شاخه‌ها به راست (پیش‌فرض همهٔ زبان‌ها — مثل حالت انگلیسی)
    case rootLeft = 1
    /// ریشه راست، شاخه‌ها به چپ
    case rootRight = 0

    var label: String {
        switch self {
        case .rootLeft: return L.tr("Root Left (Default)")
        case .rootRight: return L.tr("Root Right")
        }
    }
}

// MARK: - خروجی‌های نقشه (PNG/JPEG/PDF/HTML/Word — همه با ابزار محلی، بدون سرویس ریموت)

enum MindMapExport {

    // MARK: نام فایل

    /// نام امن برای فایل خروجی از روی عنوان صفحه
    static func safeFileName(_ title: String, fallback: String = "mindmap") -> String {
        var name = title.trimmed
        if name.isEmpty { name = fallback }
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        name = name.components(separatedBy: bad).joined(separator: "-")
        name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if name.count > 60 { name = String(name.prefix(60)) }
        return name.isEmpty ? fallback : name
    }

    // MARK: PNG/JPEG/PDF از روی عکس

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func jpegData(from image: NSImage, quality: CGFloat = 0.92) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    // MARK: مارک‌داون به HTML (برای خروجی Word)

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// تبدیل سادهٔ مارک‌داون (تیتر، فهرست، پاراگراف) به قطعهٔ HTML
    static func markdownToHTML(_ markdown: String) -> String {
        var html = ""
        var inList = false
        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") {
                if inList { html += "</ul>\n"; inList = false }
                html += "<h3>\(escapeHTML(String(line.dropFirst(4))))</h3>\n"
            } else if line.hasPrefix("## ") {
                if inList { html += "</ul>\n"; inList = false }
                html += "<h2>\(escapeHTML(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("# ") {
                if inList { html += "</ul>\n"; inList = false }
                html += "<h1>\(escapeHTML(String(line.dropFirst(2))))</h1>\n"
            } else if line.hasPrefix("- ") || line.hasPrefix("– ") {
                if !inList { html += "<ul>\n"; inList = true }
                html += "<li>\(escapeHTML(String(line.dropFirst(2))))</li>\n"
            } else if line.isEmpty {
                if inList { html += "</ul>\n"; inList = false }
            } else {
                if inList { html += "</ul>\n"; inList = false }
                html += "<p>\(escapeHTML(line))</p>\n"
            }
        }
        if inList { html += "</ul>\n" }
        return html
    }

    static func documentHTML(title: String, markdown: String, sourceURL: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="fa" dir="rtl">
        <head><meta charset="utf-8"><title>\(escapeHTML(title))</title></head>
        <body>
        <h1>\(escapeHTML(title))</h1>
        <p><a href="\(escapeHTML(sourceURL))">\(escapeHTML(sourceURL))</a></p>
        \(markdownToHTML(markdown))
        </body>
        </html>
        """
    }

    /// تبدیل HTML به docx با ابزار داخلی macOS؛ خروجی false یعنی textutil در دسترس/موفق نبود
    // MARK: HTML مستقل (بوم تک‌فایل + داده داخل یک فایل)

    /// از قالب canvas.html باندل، یک HTML مستقل می‌سازد (بدون هیچ ارجاع خارجی) و
    /// دادهٔ نقشه را با فراخوانی خودکار renderMindMap پس از بارگذاری تزریق می‌کند.
    /// برمی‌گرداند nil اگر قالب یا داده نامعتبر باشد.
    static func standaloneHTML(indexHTML: String, css: String, libraryJS: String,
                               mapJSON: String, pageTitle: String) -> String? {
        guard !mapJSON.trimmed.isEmpty,
              let data = mapJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else { return nil }
        var out = indexHTML
        // (نگه‌داشته برای سازگاری امضا/تست؛ بوم آزاد تک‌فایل است و تگ خارجی ندارد)
        _ = (css, libraryJS)
        guard let encodedString = try? JSONEncoder().encode(mapJSON),
              var jsonString = String(data: encodedString, encoding: .utf8) else { return nil }
        // JSON اینجا داخل متن یک string literal قرار می‌گیرد، نه به‌عنوان کد/شیء JS.
        // Escape `<` تا متن صفحه نتواند تگ script را ببندد؛ U+2028/2029 برای WebKit قدیمی.
        jsonString = jsonString
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        let autoload = "<script>\nwindow.addEventListener('DOMContentLoaded',function(){" +
            "try{window.renderMindMap(JSON.parse(\(jsonString)))}catch(e){}});\n</script>\n</body>"
        guard out.contains("</body>") else { return nil }
        out = out.replacingOccurrences(of: "</body>", with: autoload)
        out = out.replacingOccurrences(of: "<title>طراحی نقشه ذهنی</title>",
                                       with: "<title>\(escapeHTML(pageTitle)) — \(L.tr("Mind Map"))</title>")
        // زبان رابط خروجی مستقل از زبان UI برنامه پیروی کند
        out = out.replacingOccurrences(of: "window.__ready = true;",
                                       with: "window.__ready = true; try { setUILanguage(\(AppLanguage.current.rawValue.debugDescription)); } catch (e) {}")
        return out
    }

    /// خواندن سه فایل لازم برای خروجی HTML مستقل از باندل برنامه.
    /// در بیلد تستی (swiftc خام) باندل SwiftPM وجود ندارد و nil برمی‌گردد.
    static func bundleFiles() -> (index: String, css: String, js: String)? {
        #if SWIFT_PACKAGE
        guard let base = Bundle.module.url(forResource: "canvas", withExtension: "html",
                                           subdirectory: "MindMap")?.deletingLastPathComponent(),
              let index = try? String(contentsOf: base.appendingPathComponent("canvas.html"), encoding: .utf8)
        else { return nil }
        // بوم آزاد تک‌فایل است (بدون CSS/JS خارجی)؛ برای امضای یکسان، رشتهٔ خالی برمی‌گردانیم
        return (index, "", "")
        #else
        return nil
        #endif
    }
}
