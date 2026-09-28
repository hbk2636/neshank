import Foundation

/// End-to-end, no-persistence test: isolated WKWebView → Readability/Turndown → quality gate → AI JSON.
/// Usage:
///   swiftc -swift-version 5 -o /tmp/ny-live-map Sources/NeshankYar/Models/*.swift \
///     Sources/NeshankYar/Store/Database.swift Sources/NeshankYar/Services/*.swift Tests/live_mindmap.swift
///   /tmp/ny-live-map 'https://fa.wikipedia.org/wiki/%D9%85%D9%88%D8%B1%DB%8C%D8%B3'

@main
struct LiveMindMapTest {
    static func main() async {
        setbuf(stdout, nil)
        let rawURL = CommandLine.arguments.dropFirst().first
            ?? "https://fa.wikipedia.org/wiki/%D9%85%D9%88%D8%B1%DB%8C%D8%B3"
        guard let url = URLNormalizer.url(rawURL),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            print("❌ URL نامعتبر است")
            exit(1)
        }

        let started = Date()
        do {
            let resource = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/NeshankYar/Resources/Extractor")
            let readability = try String(contentsOf: resource.appendingPathComponent("Readability.js"), encoding: .utf8)
            let turndown = try String(contentsOf: resource.appendingPathComponent("Turndown.js"), encoding: .utf8)
            print("۱) دریافت و استخراج ایزوله با WebKit…")
            let page = try await WebPageReader.read(url, timeout: 25,
                                                    quietIntervalMilliseconds: 700,
                                                    idleCap: 12,
                                                    localLibraries: (readability, turndown))
            let quality = PageContentQuality.assess(page.markdown, title: page.title)
            print("   عنوان: \(page.title)")
            print("   URL نهایی: \(page.finalURL.absoluteString)")
            print("   روش: \(page.usedReadability ? "Readability" : "Fallback: \(page.selectedRegion)")")
            print("   Markdown: \(page.markdown.count) نویسه / \(quality.wordCount) واژه / \(page.headings.count) تیتر")
            print("   تیترها: \(page.headings.prefix(18).joined(separator: " | "))")
            print("   خطوط تیتر Markdown: \(page.markdown.components(separatedBy: .newlines).filter { $0.hasPrefix("#") }.prefix(18).joined(separator: " | "))")
            print("   HTML h2 count: \(page.contentHTML.components(separatedBy: "<h2").count - 1)")
            print("   دروازهٔ کیفیت: \(quality.isUsable ? "قبول" : "رد") — \(quality.explanation)")
            print("   پیش‌نمایش: \(page.markdown.prefix(320).replacingOccurrences(of: "\n", with: " ⏎ "))")
            guard quality.isUsable else { print("❌ کیفیت متن کافی نیست"); exit(2) }
            if CommandLine.arguments.contains("--extract-only") {
                print("✅ استخراج-only پایان سرتاسری در \(Int(Date().timeIntervalSince(started))) ثانیه")
                exit(0)
            }

            print("۲) تولید JSON با AI موجود…")
            let result = try await MindMapAIService.generate(page: page,
                                                              quality: quality,
                                                              config: AIConfig.load(),
                                                              session: AIClient.newSession())
            print("   model: \(result.document.meta.model)")
            print("   root: \(result.document.root.text)")
            print("   گره‌ها: \(result.nodeCount)، شاخه‌ها: \(result.document.root.children.count)")
            print("   زبان: \(result.document.meta.language)، خلاصه شد: \(result.wasSummarized)، fallback: \(result.wasFallback)")
            if let warning = result.warning { print("   هشدار: \(warning)") }
            for child in result.document.root.children.prefix(8) {
                print("   • \(child.text) [\(child.children.count) زیرگره]")
            }
            print("   JSON معتبر: \(result.json.count) نویسه")
            print("✅ پایان سرتاسری در \(Int(Date().timeIntervalSince(started))) ثانیه")
            exit(0)
        } catch {
            print("❌ \(error.localizedDescription)")
            exit(3)
        }
    }
}
