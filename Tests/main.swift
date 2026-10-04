import Foundation

// Functional test suite for the logic layer (no UI) — compile and run with swiftc.

setbuf(stdout, nil)

var failures = 0
func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond {
        print("✅ \(name)")
    } else {
        failures += 1
        print("❌ \(name)  \(detail)")
    }
}

// MARK: 1) URL normalization

let stripped = URLNormalizer.url("https://example.com/a?utm_source=x&utm_medium=y&keep=1")?.absoluteString
check("tracking parameters are stripped", stripped == "https://example.com/a?keep=1", stripped ?? "nil")

check("https is added when the scheme is missing",
      URLNormalizer.url("example.com/x")?.absoluteString == "https://example.com/x",
      URLNormalizer.url("example.com/x")?.absoluteString ?? "nil")

check("www is removed from the domain",
      URLNormalizer.domain(URL(string: "https://www.Example.com/page")!) == "example.com",
      URLNormalizer.domain(URL(string: "https://www.Example.com/page")!))

check("invalid URL is rejected", URLNormalizer.url("   ") == nil)
check("fbclid is removed",
      URLNormalizer.url("https://s.io/p?fbclid=abc&id=9")?.absoluteString == "https://s.io/p?id=9",
      URLNormalizer.url("https://s.io/p?fbclid=abc&id=9")?.absoluteString ?? "nil")

// MARK: 2) Browser HTML parser

let sample = """
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<TITLE>Bookmarks</TITLE>
<DL><p>
    <DT><H3>Development</H3>
    <DL><p>
        <DT><A HREF="https://swift.org/blog/" ADD_DATE="123">Swift Blog &amp; News</A>
        <DD>Official blog
        <DT><A HREF='https://apple.com'>Apple</A>
    </DL><p>
    <DT><A HREF="https://example.org/alone">No folder</A>
</DL><p>
"""

let entries = NetscapeHTML.parse(sample)
print("<<parsed: \(entries.count) -> \(entries.map { "\($0.folder ?? "-")|\($0.title)|\($0.url)|\($0.note ?? "-")" }))>>")
check("input bookmark count", entries.count == 3, "got \(entries.count)")
check("folder assignment", entries.first?.folder == "Development", entries.first?.folder ?? "nil")
check("title extracted (entity decoded)",
      entries.first?.title == "Swift Blog & News", entries.first?.title ?? "nil")
check("<DD> note", entries.first?.note == "Official blog", entries.first?.note ?? "nil")
check("single-quoted attribute", entries.count > 1 ? entries[1].url == "https://apple.com" : false,
      entries.count > 1 ? entries[1].url : "missing")
check("bookmark without folder", entries.count > 2 ? entries[2].folder == nil : false,
      entries.count > 2 ? (entries[2].folder ?? "nil") : "missing")

// MARK: 3) HTML export and round-trip

let exported = NetscapeHTML.render(
    entries: entries.map { (folder: $0.folder, title: $0.title, url: $0.url, note: $0.note ?? "") }
)
check("NETSCAPE header in export", exported.contains("NETSCAPE-Bookmark-file-1"))
let roundTrip = NetscapeHTML.parse(exported)
check("export -> import round-trip", roundTrip.count == entries.count, "got \(roundTrip.count)")
check("folder survives round-trip", roundTrip.contains { $0.folder == "Development" })
check("folderless bookmark in export", roundTrip.contains { $0.folder == nil })

// MARK: 4) HTML entity decoding

check("basic unescape",
      HTMLCodec.unescape("a &amp; b &lt;c&gt; &quot;d&quot;") == "a & b <c> \"d\"",
      HTMLCodec.unescape("a &amp; b &lt;c&gt; &quot;d&quot;"))
check("decimal numeric character reference", HTMLCodec.unescape("&#1740;") == "\u{06CC}", HTMLCodec.unescape("&#1740;"))
check("hex numeric character reference", HTMLCodec.unescape("&#x627;") == "\u{0627}", HTMLCodec.unescape("&#x627;"))
check("Arabic decimal character reference", HTMLCodec.unescape("&#1610;") == "\u{064A}", HTMLCodec.unescape("&#1610;"))

// MARK: 5) Full-page text extraction (archive + deep search)

let samplePage = """
<html><head><title>x</title><style>body{color:red}</style>
<script>var secret=1;</script></head>
<body><nav>Site menu</nav><h1>Page title</h1>
<p>First paragraph &amp; second</p><ul><li>Item one</li></ul>
<img src="a.png"><p>Second paragraph</p><footer>Footer text</footer></body></html>
"""

let pageText = HTMLText.extract(from: samplePage)
check("script/style/nav/footer removed from text", !pageText.contains("var secret") && !pageText.contains("color:red")
      && !pageText.contains("Site menu") && !pageText.contains("Footer text"), pageText)
check("entities decoded in text", pageText.contains("First paragraph & second"), pageText)
check("li items become a bulleted list", pageText.contains("• Item one"), pageText)
check("no HTML tags in output", !pageText.contains("<p>") && !pageText.contains("<h1>"), pageText)
check("paragraphs on separate lines", pageText.contains("\nSecond paragraph"), pageText)
check("text length cap", HTMLText.extract(from: String(repeating: "word ", count: 200_000)).count <= HTMLText.maxChars)

// MARK: 6) Page metadata fetch (network)

func awaitInfo(_ label: String, url: String, validate: @escaping @Sendable (PageMetaResult) -> Bool) {
    let sem = DispatchSemaphore(value: 0)
    var captured: PageMetaResult?
    let task = Task.detached {
        captured = await PageMeta.fetch(URL(string: url)!)
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 25)
    task.cancel()
    guard let meta = captured else {
        check(label, false, "no response")
        return
    }
    check(label, validate(meta), "title=\(meta.title ?? "nil") icon=\(meta.faviconURL?.absoluteString ?? "nil")")
}

awaitInfo("fetch title and favicon from swift.org", url: "https://swift.org") { meta in
    !(meta.title ?? "").isEmpty && meta.faviconURL != nil
}

awaitInfo("fetch og:image from a Persian-language site",
          url: "https://fa.wikipedia.org/wiki/%D8%A7%D9%BE%D9%84") { meta in
    !(meta.title ?? "").isEmpty && meta.imageURL != nil
}

// MARK: 7) Link health check

func awaitHealth(_ label: String, url: String, expect: LinkChecker.Health) {
    let sem = DispatchSemaphore(value: 0)
    var health: LinkChecker.Health = .unknown
    let task = Task.detached {
        health = await LinkChecker.check(url)
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 30)
    task.cancel()
    switch health {
    case .unknown:
        print("⚠️ \(label) — no definitive answer (network/limit) — expected: \(expect)")
    case .alive, .dead:
        check(label, health == expect, "got \(health) expected \(expect)")
    }
}

awaitHealth("live link reported alive", url: "https://swift.org", expect: .alive)
awaitHealth("404 link reported dead", url: "https://swift.org/this-page-should-not-exist-xyz", expect: .dead)

// MARK: 8) Real page screenshot (reading & archive pack)

// WKWebView must run on the main thread, so we spin the run loop
// until MainActor work finishes, without deadlocking the main thread.
var shotPath: String?
let shotDone = DispatchSemaphore(value: 0)

Task { @MainActor in
    shotPath = await Screenshotter.capture(URL(string: "https://swift.org")!, key: "test-shot")
    shotDone.signal()
}

let shotEnd = Date().addingTimeInterval(45)
while shotDone.wait(timeout: .now() + 0.05) != .success {
    if Date() > shotEnd { break }
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}

if let path = shotPath {
    let size = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int) ?? 0
    check("real page screenshot captured and saved",
          FileManager.default.fileExists(atPath: path) && size > 3000,
          "size=\(size)")
    try? FileManager.default.removeItem(atPath: path)
} else {
    check("real page screenshot captured and saved", false, "nil")
}

// MARK: 9) AI assistant (request, prompt and live connection)

let aiCfg = AIConfig(baseURL: "https://api.openai.com/v1",
                     apiKey: "test-key",
                     model: "gpt-4o-mini",
                     profile: "")

check("no default cloud is baked in (BYO provider) and endpoint derives from the base URL",
      AIConfig.defaultBaseURL.isEmpty
        && aiCfg.endpoint?.absoluteString == "https://api.openai.com/v1/chat/completions",
      aiCfg.endpoint?.absoluteString ?? "nil")
check("configured model is passed through", aiCfg.model == "gpt-4o-mini")

if let aiReq = AIClient.makeRequest(config: aiCfg, session: "sess-123",
                                    messages: [.user("hello"), .assistant("hi")]) {
    check("x-opencode-session header is sent",
          aiReq.value(forHTTPHeaderField: "x-opencode-session") == "sess-123")
    check("Authorization header uses Bearer",
          aiReq.value(forHTTPHeaderField: "Authorization") == "Bearer \("test-key")")
    check("User-Agent identifies the app",
          aiReq.value(forHTTPHeaderField: "User-Agent")?.contains("Neshank") == true)
    let bodyText = aiReq.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    check("request body carries model and messages",
          bodyText.contains("gpt-4o-mini") && bodyText.contains("hello") && bodyText.contains("assistant"),
          String(bodyText.prefix(160)))
    check("request method is POST", aiReq.httpMethod == "POST")
} else {
    check("build assistant request", false, "nil")
}

let sysPrompt = AIClient.systemPrompt(
    profile: "I am a UI designer; budget up to 2,000,000",
    title: "Dell color-accurate monitor",
    url: "https://example.com/p/9",
    domain: "example.com",
    note: "for the home office",
    tags: ["shopping", "tech"],
    savedAt: "2026-09-23",
    pageContent: "This monitor has an IPS panel and 99% sRGB coverage."
)
check("prompt contains the bookmark URL", sysPrompt.contains("https://example.com/p/9"))
check("prompt contains the user profile", sysPrompt.contains("UI designer"))
check("prompt contains the page text", sysPrompt.contains("IPS panel"))
check("prompt contains note and tags",
      sysPrompt.contains("home office") && sysPrompt.contains("shopping"))
check("prompt shows the fallback when page text is missing (Persian app text via escapes)",
      AIClient.systemPrompt(profile: "", title: "t", url: "https://x.io", domain: "x.io",
                            note: "", tags: [], savedAt: "", pageContent: nil)
        .contains("\u{0645}\u{0648}\u{062C}\u{0648}\u{062F} \u{0646}\u{06CC}\u{0633}\u{062A}"))
check("clipping a long text respects the cap",
      AIClient.clip(String(repeating: "A", count: 5000), 1000).count <= 1000
        && AIClient.clip("short", 1000) == "short")

check("quick actions are non-empty and unique",
      AIClient.QuickAction.all.count >= 5
        && AIClient.QuickAction.all.allSatisfy { !$0.prompt.isBlank && !$0.title.isBlank }
        && Set(AIClient.QuickAction.all.map(\.id)).count == AIClient.QuickAction.all.count)

// live connection (default key or key passed through the environment)
var liveCfg = AIConfig.load()
if let envKey = ProcessInfo.processInfo.environment["OPENCODE_API_KEY"], !envKey.isBlank {
    liveCfg.apiKey = envKey
}
if liveCfg.isConfigured {
    let semAI = DispatchSemaphore(value: 0)
    var answerAI: String?
    var errorAI: String?
    let taskAI = Task.detached {
        do {
            answerAI = try await AIClient.chat(config: liveCfg,
                                               session: AIClient.newSession(),
                                               messages: [.user("reply with only: connected")],
                                               maxTokens: 3000)
        } catch {
            errorAI = String(describing: error)
        }
        semAI.signal()
    }
    _ = semAI.wait(timeout: .now() + 70)
    taskAI.cancel()
    check("live completion returns a model answer",
          !(answerAI ?? "").isEmpty,
          answerAI.map { String($0.prefix(60)) } ?? (errorAI ?? "nil"))
} else {
    print("ℹ️ live assistant test — key not configured; skipped")
}

// MARK: 10) Sample bookmark fixture
func makeBookmark(_ id: Int64,
                  _ title: String,
                  _ domain: String,
                  tags: [String] = [],
                  note: String = "",
                  folder: Int64? = nil) -> Bookmark {
    var b = Bookmark(row: DBRow(values: [
        "id": .int(id),
        "url": .text("https://\(domain)/p/\(id)"),
        "title": .text(title),
        "note": .text(note),
        "domain": .text(domain),
        "folder_id": folder.map { SQLValue.int($0) } ?? .null,
        "starred": .int(0),
        "is_read": .int(0),
        "is_archived": .int(0),
        "is_dead": .int(0),
        "created_at": .real(Date().timeIntervalSince1970),
        "updated_at": .real(Date().timeIntervalSince1970)
    ]))
    b.tags = tags
    return b
}

let resinBookmark = makeBookmark(1, "Clear epoxy resin", "resin-shop.ir",
                                 tags: ["resin"], note: "for composites")

// library answer sources
check("library answer source count",
      AIAdvisor.citations([AIAdvisor.ContextItem(bookmark: resinBookmark)]).first?.bookmarkId == 1)
check("library prompt numbers its sources",
      AIAdvisor.libraryUserPrompt(question: "resin?",
                                  items: [AIAdvisor.ContextItem(bookmark: resinBookmark)]).contains("[1]"))

// chat text
check("auto chat title is truncated",
      ChatText.autoTitle(String(repeating: "resin ", count: 40)).count <= 43)
check("message preview is single-line and short",
      ChatText.clean("line one\nline two", limit: 12).count <= 13)
check("empty message has no preview", ChatText.clean(nil).isEmpty)

// MARK: 11) Text quality and article extraction (offline)

// quality scoring: a title-only or menu-only page is not trustworthy
let titleOnly = PageContentQuality.assess("Clear epoxy resin | Home | Products | Contact us",
                                          title: "Clear epoxy resin")
check("quality: title-only text is rejected", !titleOnly.isUsable, titleOnly.explanation)

let articleText = """
Clear epoxy resin is a good choice for home moulding because the cure time is controllable.
Low viscosity lets air bubbles leave the mixture faster.
The mix ratio must be exact, for example two parts resin to one part hardener.
At room temperature a full cure takes about twenty-four hours.
For floor projects the layer must stay within the allowed thickness because the reaction exotherm rises.
""" + "\n" + (1...40).map { "Explanatory sentence \($0) about the curing process and resin safety." }.joined(separator: "\n")
let goodQuality = PageContentQuality.assess(articleText, title: "Clear epoxy resin")
check("quality: article text is trustworthy", goodQuality.isUsable, goodQuality.explanation)
check("quality: Arabic letters and ZWNJ normalized (Unicode escapes)", PageContentQuality.normalize("\u{0639}\u{0644}\u{064A}\u{200C}\u{0645}\u{0631}\u{0627}\u{062F}").contains("\u{0639}\u{0644}\u{06CC} \u{0645}\u{0631}\u{0627}\u{062F}"))

// extraction picks the article instead of the whole noisy page
let noisyHTML = """
<html><head><title>Article</title></head><body>
<nav>Home | Shop | Contact us | Sign in | Shopping cart</nav>
<article><h1>Resin curing guide</h1><p>\(articleText.split(separator: "\n").prefix(3).joined(separator: " "))</p></article>
<footer>All rights reserved — newsletter — social media</footer>
</body></html>
"""
let mainText = HTMLText.extractMain(from: noisyHTML)
check("extraction: article text selected", mainText.contains("Low viscosity"), String(mainText.prefix(80)))
check("extraction: side menu removed", !mainText.contains("Shopping cart"))

// main extraction: class-based menus/footers and link-heavy containers must stay out
let divMenuHTML = """
<html><body>
<div class="main-menu"><ul><li><a href="/">Home</a></li><li><a href="/shop">Store</a></li><li><a href="/login">Sign in</a></li></ul></div>
<div id="content" class="entry-content">
<h1>Fiberglass layup tutorial</h1>
<p>Fiberglass layup is one of the most common ways to build composite parts, where epoxy resin acts as the binder and the protector. Layup quality depends on several factors including the resin-to-hardener mix ratio, and ambient temperature seriously affects the final cure.</p>
<p>To start, clean the work surface and press the glass cloth layers down by hand so no air bubbles remain; then pour the resin onto the surface slowly.</p>
</div>
<div class="site-footer"><p>All rights reserved</p><p>About us — Contact — Advertising</p></div>
</body></html>
"""
let divMenuText = HTMLText.extractMain(from: divMenuHTML)
check("extraction: div-based menu removed", !divMenuText.contains("Store") && !divMenuText.contains("Sign in"), divMenuText)
check("extraction: class-based footer removed", !divMenuText.contains("All rights reserved"), divMenuText)
check("extraction: main text kept", divMenuText.contains("Fiberglass layup"), divMenuText)

let headerNavHTML = """
<html><body>
<header><nav><a href="/a">Social media</a> <a href="/b">Contact</a> <a href="/c">Search</a></nav></header>
<main><p>This is the main article text and it has several sentences so it passes the length threshold and is recognized as real content. Epoxy resin is used across many industries and choosing the right type depends fully on the project.</p><p>The second paragraph adds weight to the main candidate; low viscosity improves penetration and a longer working time makes more precise work possible.</p></main>
</body></html>
"""
let headerNavText = HTMLText.extractMain(from: headerNavHTML)
check("extraction: nav inside header removed", !headerNavText.contains("Social media"), headerNavText)
check("extraction: main text kept", headerNavText.contains("low viscosity"), headerNavText)

let linkFarmHTML = """
<html><body>
<div class="links"><a href="/1">Epoxy</a> <a href="/2">Hardener</a> <a href="/3">Glass cloth</a> <a href="/4">Coat</a> <a href="/5">Matte</a> <a href="/6">Roll</a> <a href="/7">Catalog</a> <a href="/8">Price</a> <a href="/9">Buy</a> <a href="/10">Sell</a> <a href="/11">Primer</a> <a href="/12">Polyester</a></div>
<article><p>A long analytical text comparing epoxy and polyester resin that has full sentences and is worth reading; viscosity, gel time and final strength are the three main selection criteria and we open each one below.</p><p>Epoxy has better adhesion to fiberglass but costs more; polyester cures faster yet smells stronger.</p></article>
</body></html>
"""
let farmText = HTMLText.extractMain(from: linkFarmHTML)
check("extraction: link-heavy container not trusted", farmText.contains("better adhesion") && !farmText.contains("Catalog"), farmText)

let fallbackHTML = """
<html><body>
<div class="top-nav"><a href="/">Home</a><a href="/x">Reports</a><a href="/y">About</a></div>
<p>This is a simple page without semantic structure but its main text is worth saving and must stay.</p>
<p>Second paragraph of the simple page; static extraction must return the text without the menu.</p>
<div class="footer-bar"><a href="/f">Privacy</a></div>
</body></html>
"""
let fbText = HTMLText.extractMain(from: fallbackHTML)
check("extraction fallback: text kept", fbText.contains("worth saving"), fbText)
check("extraction fallback: menu removed", !fbText.contains("Privacy") && !fbText.contains("Reports"), fbText)


// request body: reasoning control (key for non-empty answers on reasoning models)
if let req = AIClient.makeRequest(config: AIConfig(baseURL: "https://api.openai.com/v1",
                                                   apiKey: "k",
                                                   model: "gpt-4o-mini",
                                                   profile: ""),
                                  session: "s",
                                  messages: [.user("hello")],
                                  maxTokens: 8000,
                                  reasoningEffort: "low"),
   let bodyData = req.httpBody,
   let bodyObj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
    check("request: reasoning_effort goes into the body", bodyObj["reasoning_effort"] as? String == "low")
    check("request: max_tokens goes into the body", bodyObj["max_tokens"] as? Int == 8000)
} else {
    check("request: reasoning_effort goes into the body", false)
}
if let req = AIClient.makeRequest(config: AIConfig(baseURL: "https://api.openai.com/v1",
                                                   apiKey: "k",
                                                   model: "gpt-4o-mini",
                                                   profile: ""),
                                  session: "s",
                                  messages: [.user("hello")]),
   let bodyData = req.httpBody,
   let bodyObj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
    check("request: without an explicit value the reasoning field stays null",
          bodyObj["reasoning_effort"] is NSNull || bodyObj["reasoning_effort"] == nil)
} else {
    check("request: without an explicit value the reasoning field stays null", false)
}

// MARK: 12) Mind-map outputs (file names, themes, direction, HTML/Word)

check("themes: ten themes with labels", MindMapTheme.allCases.count == 10
      && MindMapTheme.allCases.allSatisfy { !$0.label.isBlank })
check("themes: dark/light mapping", MindMapTheme.forColorScheme(dark: true) == .dark
      && MindMapTheme.forColorScheme(dark: false) == .light)
check("themes: names match THEMES on the JS side",
      Set(MindMapTheme.allCases.map(\.rawValue))
        == ["light", "dark", "forest", "ocean", "sunset", "lavender", "mono", "sand", "sakura", "mint"])
check("layouts: six layouts with labels", MindMapLayout.allCases.count == 6
      && MindMapLayout.allCases.allSatisfy { !$0.label.isBlank && !$0.icon.isBlank })
check("layouts: names match LAYOUT_NAMES on the JS side",
      Set(MindMapLayout.allCases.map(\.rawValue)) == ["tree", "org", "radial", "outline", "timeline", "mindmap"])
check("layouts: layout read from map JSON",
      MindMapLayout.fromJSON(#"{"meta":{"layout":"radial"},"root":{"id":"root","text":"r","children":[]}}"#) == .radial
      && MindMapLayout.fromJSON(#"{"meta":{},"root":{}}"#) == nil
      && MindMapLayout.fromJSON(#"{"meta":{"layout":"unknown"},"root":{}}"#) == nil)
check("direction: rootLeft raw value is 1", MindMapDirection.rootLeft.rawValue == 1)
check("direction: rootRight raw value is 0", MindMapDirection.rootRight.rawValue == 0)

check("file name: forbidden characters replaced",
      MindMapExport.safeFileName("Map: resin/epoxy?") == "Map- resin-epoxy-")
check("file name: blank falls back to default", MindMapExport.safeFileName("   ") == "mindmap")
check("file name: length cap", MindMapExport.safeFileName(String(repeating: "a", count: 200)).count <= 60)

let mdSample = "# Heading\n\n## Subheading\n\n- Item one\n- Item two\n\nSimple paragraph"
let htmlFrag = MindMapExport.markdownToHTML(mdSample)
check("MD->HTML: headings", htmlFrag.contains("<h1>Heading</h1>") && htmlFrag.contains("<h2>Subheading</h2>"))
check("MD->HTML: list", htmlFrag.contains("<ul>") && htmlFrag.contains("<li>Item one</li>"))
check("MD->HTML: paragraph", htmlFrag.contains("<p>Simple paragraph</p>"))
check("MD->HTML: character escaping",
      MindMapExport.markdownToHTML("<b>no</b> & <i>yes</i>").contains("&lt;b&gt;no&lt;/b&gt;"))

let docHTML = MindMapExport.documentHTML(title: "Map", markdown: mdSample, sourceURL: "https://x.ir/")
check("HTML document: title, URL and body", docHTML.contains("<title>Map</title>")
      && docHTML.contains("https://x.ir/") && docHTML.contains("<h1>Heading</h1>"))

// The placeholder title below must byte-match the hard-coded template title in
// MindMapExport.standaloneHTML; \u escapes keep this file ASCII-only.
let fakeIndex = """
<html><head><title>\u{637}\u{631}\u{627}\u{62D}\u{6CC} \u{646}\u{642}\u{634}\u{647} \u{630}\u{647}\u{646}\u{6CC}</title><style>.node{}</style></head><body>
<div id="viewport"></div>
<script>window.renderMindMap=function(){};</script>
</body></html>
"""
let mapJSON = "{\"meta\":{\"title\":\"t\"},\"root\":{\"id\":\"root\",\"text\":\"Root\",\"children\":[]}}"
if let standalone = MindMapExport.standaloneHTML(indexHTML: fakeIndex, css: "/*css*/",
                                                 libraryJS: "/*js*/", mapJSON: mapJSON,
                                                 pageTitle: "My Map") {
    check("standalone HTML: data only via JSON.parse and an auto-call",
          standalone.contains("renderMindMap(JSON.parse(") && standalone.contains("\\\"meta\\\""))
    check("standalone HTML: page title", standalone.contains("My Map — \(L.tr("Mind Map"))"))
    check("standalone HTML: no remote references", !standalone.contains("src=\"./") && !standalone.contains("href=\"./"))
    check("standalone HTML: template stays untouched", standalone.contains("window.renderMindMap=function(){}"))
} else {
    check("standalone HTML: built", false)
}
check("standalone HTML: invalid JSON rejected",
      MindMapExport.standaloneHTML(indexHTML: fakeIndex, css: "", libraryJS: "",
                                   mapJSON: "not-json", pageTitle: "x") == nil)
let hostileMapJSON = "{\"meta\":{},\"root\":{\"id\":\"root\",\"text\":\"</script><script>alert(1)</script>\",\"children\":[]}}"
let safeStandalone = MindMapExport.standaloneHTML(indexHTML: fakeIndex, css: "", libraryJS: "",
                                                  mapJSON: hostileMapJSON, pageTitle: "x") ?? ""
check("standalone HTML: node content cannot break out of script",
      !safeStandalone.contains("</script><script>alert(1)") && safeStandalone.contains("\\u003c"))

// MARK: 13) Schema and map storage independent of bookmarks

let mapRecordJSON = """
{"meta":{"title":"Mauritius","sourceUrl":"https://en.wikipedia.org/wiki/Mauritius",
"createdAt":"2026-09-27T00:00:00Z","model":"deepseek-v4.1-flash","language":"fa"},
"root":{"id":"root","text":"Mauritius","children":[
  {"id":"n1","text":"Geography","children":[{"id":"n1a","text":"Indian Ocean","children":[]}]},
  {"id":"n2","text":"History","children":[]}]}}
"""
if let data = mapRecordJSON.data(using: .utf8),
   let document = try? JSONDecoder().decode(MindMapDocument.self, from: data) {
    check("map JSON: meta and tree decode", document.meta.title == "Mauritius" && document.root.children.count == 2)
    check("map JSON: children are independent and nested", document.root.children[0].children.first?.text == "Indian Ocean")
} else {
    check("map JSON: meta and tree decode", false)
}

let mapRow = DBRow(values: [
    "id": .int(91),
    "title": .text("Mauritius — Geography"),
    "source_url": .text("https://en.wikipedia.org/wiki/Mauritius"),
    "normalized_url": .text("https://en.wikipedia.org/wiki/Mauritius"),
    "content_hash": .text("abc123"),
    "mind_map_json": .text(mapRecordJSON),
    "raw_markdown": .text("# Mauritius\n\n## Geography\n\n## History"),
    "model": .text("deepseek-v4.1-flash"),
    "language": .text("fa"),
    "created_at": .real(1_790_000_000),
    "updated_at": .real(1_790_000_100)
])
let independentMap = MindMapRecord(row: mapRow)
check("map record: id independent of bookmarks", independentMap.id == 91 && independentMap.displayNodeCount == 4)
check("map record: source URL and text are preserved",
      independentMap.sourceURL.contains("wikipedia.org") && independentMap.rawMarkdown.contains("## Geography"))
check("mind-map prompt contains no demo leftovers",
      !MindMapAIService.prompt.contains("sample map") && !MindMapAIService.prompt.contains("epoxy resin"))

// MARK: Result

print(failures == 0 ? "\n🎉 all tests passed" : "\n❗ \(failures) test(s) failed")
exit(failures == 0 ? 0 : 1)
