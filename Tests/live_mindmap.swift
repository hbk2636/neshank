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
            print("❌ Invalid URL")
            exit(1)
        }

        let started = Date()
        do {
            let resource = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/NeshankYar/Resources/Extractor")
            let readability = try String(contentsOf: resource.appendingPathComponent("Readability.js"), encoding: .utf8)
            let turndown = try String(contentsOf: resource.appendingPathComponent("Turndown.js"), encoding: .utf8)
            print("1) Fetch + isolated extraction via WebKit…")
            let page = try await WebPageReader.read(url, timeout: 25,
                                                    quietIntervalMilliseconds: 700,
                                                    idleCap: 12,
                                                    localLibraries: (readability, turndown))
            let quality = PageContentQuality.assess(page.markdown, title: page.title)
            print("   title: \(page.title)")
            print("   final URL: \(page.finalURL.absoluteString)")
            print("   method: \(page.usedReadability ? "Readability" : "Fallback: \(page.selectedRegion)")")
            print("   Markdown: \(page.markdown.count) chars / \(quality.wordCount) words / \(page.headings.count) headings")
            print("   headings: \(page.headings.prefix(18).joined(separator: " | "))")
            print("   markdown heading lines: \(page.markdown.components(separatedBy: .newlines).filter { $0.hasPrefix("#") }.prefix(18).joined(separator: " | "))")
            print("   HTML h2 count: \(page.contentHTML.components(separatedBy: "<h2").count - 1)")
            print("   quality gate: \(quality.isUsable ? "accept" : "reject") — \(quality.explanation)")
            print("   preview: \(page.markdown.prefix(320).replacingOccurrences(of: "\n", with: " ⏎ "))")
            guard quality.isUsable else { print("❌ Not enough text quality"); exit(2) }
            if CommandLine.arguments.contains("--extract-only") {
                print("✅ extraction-only end-to-end in \(Int(Date().timeIntervalSince(started)))s")
                exit(0)
            }

            print("2) Building JSON with the available AI…")
            let result = try await MindMapAIService.generate(page: page,
                                                              quality: quality,
                                                              config: AIConfig.load(),
                                                              session: AIClient.newSession())
            print("   model: \(result.document.meta.model)")
            print("   root: \(result.document.root.text)")
            print("   nodes: \(result.nodeCount), top-level branches: \(result.document.root.children.count)")
            print("   language: \(result.document.meta.language), summarized: \(result.wasSummarized), fallback: \(result.wasFallback)")
            if let warning = result.warning { print("   warning: \(warning)") }
            for child in result.document.root.children.prefix(8) {
                print("   • \(child.text) [\(child.children.count) children]")
            }
            print("   valid JSON: \(result.json.count) chars")
            print("✅ end-to-end in \(Int(Date().timeIntervalSince(started)))s")
            exit(0)
        } catch {
            print("❌ \(error.localizedDescription)")
            exit(3)
        }
    }
}
