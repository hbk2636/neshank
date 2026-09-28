import Foundation

// تست عملکردی لایهٔ منطق (بدون UI) — با swiftc کامپایل و اجرا می‌شود.

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

// MARK: ۱) نرمال‌سازی آدرس

let stripped = URLNormalizer.url("https://example.com/a?utm_source=x&utm_medium=y&keep=1")?.absoluteString
check("حذف پارامترهای ردیابی", stripped == "https://example.com/a?keep=1", stripped ?? "nil")

check("افزودن https به آدرس بدون scheme",
      URLNormalizer.url("example.com/x")?.absoluteString == "https://example.com/x",
      URLNormalizer.url("example.com/x")?.absoluteString ?? "nil")

check("حذف www از دامنه",
      URLNormalizer.domain(URL(string: "https://www.Example.com/page")!) == "example.com",
      URLNormalizer.domain(URL(string: "https://www.Example.com/page")!))

check("آدرس نامعتبر رد می‌شود", URLNormalizer.url("   ") == nil)
check("fbclid حذف شود",
      URLNormalizer.url("https://s.io/p?fbclid=abc&id=9")?.absoluteString == "https://s.io/p?id=9",
      URLNormalizer.url("https://s.io/p?fbclid=abc&id=9")?.absoluteString ?? "nil")

// MARK: ۲) پارسر HTML مرورگر

let sample = """
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<TITLE>Bookmarks</TITLE>
<DL><p>
    <DT><H3>توسعه</H3>
    <DL><p>
        <DT><A HREF="https://swift.org/blog/" ADD_DATE="123">Swift Blog &amp; News</A>
        <DD>وبلاگ رسمی
        <DT><A HREF='https://apple.com'>Apple</A>
    </DL><p>
    <DT><A HREF="https://example.org/alone">بدون پوشه</A>
</DL><p>
"""

let entries = NetscapeHTML.parse(sample)
print("<<parsed: \(entries.count) -> \(entries.map { "\($0.folder ?? "-")|\($0.title)|\($0.url)|\($0.note ?? "-")" }))>>")
check("شمارش نشانک‌های ورودی", entries.count == 3, "got \(entries.count)")
check("انتساب پوشه", entries.first?.folder == "توسعه", entries.first?.folder ?? "nil")
check("عنوان انتزاع‌شده (بدون entity)",
      entries.first?.title == "Swift Blog & News", entries.first?.title ?? "nil")
check("توضیح <DD>", entries.first?.note == "وبلاگ رسمی", entries.first?.note ?? "nil")
check("نقل‌قول تکی", entries.count > 1 ? entries[1].url == "https://apple.com" : false,
      entries.count > 1 ? entries[1].url : "missing")
check("نشانک بدون پوشه", entries.count > 2 ? entries[2].folder == nil : false,
      entries.count > 2 ? (entries[2].folder ?? "nil") : "missing")

// MARK: ۳) خروجی HTML و رندتریپ

let exported = NetscapeHTML.render(
    entries: entries.map { (folder: $0.folder, title: $0.title, url: $0.url, note: $0.note ?? "") }
)
check("سربرگ NETSCAPE در خروجی", exported.contains("NETSCAPE-Bookmark-file-1"))
let roundTrip = NetscapeHTML.parse(exported)
check("رندتریپ خروجی→ورودی", roundTrip.count == entries.count, "got \(roundTrip.count)")
check("پوشه در رندتریپ حفظ می‌شود", roundTrip.contains { $0.folder == "توسعه" })
check("نشانک بدون پوشه در خروجی", roundTrip.contains { $0.folder == nil })

// MARK: ۴) کدگشایی HTML

check("unescape پایه",
      HTMLCodec.unescape("a &amp; b &lt;c&gt; &quot;d&quot;") == "a & b <c> \"d\"",
      HTMLCodec.unescape("a &amp; b &lt;c&gt; &quot;d&quot;"))
check("کاراکتر عددی دهگی", HTMLCodec.unescape("&#1740;") == "ی", HTMLCodec.unescape("&#1740;"))
check("کاراکتر شانزدهگی", HTMLCodec.unescape("&#x627;") == "ا", HTMLCodec.unescape("&#x627;"))
check("کاراکتر عربی دهگی", HTMLCodec.unescape("&#1610;") == "ي", HTMLCodec.unescape("&#1610;"))

// MARK: ۵) استخراج متن کامل صفحه (آرشیو + جستجوی عمیق)

let samplePage = """
<html><head><title>x</title><style>body{color:red}</style>
<script>var secret=1;</script></head>
<body><nav>فهرست منو</nav><h1>عنوان صفحه</h1>
<p>اولین پاراگراف &amp; دومی</p><ul><li>ردیف یک</li></ul>
<img src="a.png"><p>پاراگراف دوم</p><footer>متن پابرگ</footer></body></html>
"""

let pageText = HTMLText.extract(from: samplePage)
check("حذف script/style/nav/footer از متن", !pageText.contains("var secret") && !pageText.contains("color:red")
      && !pageText.contains("فهرست منو") && !pageText.contains("متن پابرگ"), pageText)
check("کدگشایی entity در متن", pageText.contains("اولین پاراگراف & دومی"), pageText)
check("تبدیل li به فهرست گلوله‌ای", pageText.contains("• ردیف یک"), pageText)
check("بدون تگ HTML در خروجی", !pageText.contains("<p>") && !pageText.contains("<h1>"), pageText)
check("پاراگراف‌ها در خطوط جدا", pageText.contains("\nپاراگراف دوم"), pageText)
check("سقف طول متن", HTMLText.extract(from: String(repeating: "کاراکتر ", count: 200_000)).count <= HTMLText.maxChars)

// MARK: ۶) دریافت متادیتای صفحه (شبکه)

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
        check(label, false, "بدون پاسخ")
        return
    }
    check(label, validate(meta), "title=\(meta.title ?? "nil") icon=\(meta.faviconURL?.absoluteString ?? "nil")")
}

awaitInfo("دریافت عنوان و فاوآیکون از swift.org", url: "https://swift.org") { meta in
    !(meta.title ?? "").isEmpty && meta.faviconURL != nil
}

awaitInfo("دریافت og:image از یک سایت فارسی",
          url: "https://fa.wikipedia.org/wiki/%D8%A7%D9%BE%D9%84") { meta in
    !(meta.title ?? "").isEmpty && meta.imageURL != nil
}

// MARK: ۷) بررسی سلامت لینک

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
        print("⚠️ \(label) — پاسخ قطعی نرسید (شبکه/محدودیت) — انتظار: \(expect)")
    case .alive, .dead:
        check(label, health == expect, "got \(health) expected \(expect)")
    }
}

awaitHealth("لینک سالم زنده گزارش شود", url: "https://swift.org", expect: .alive)
awaitHealth("لینک 404 مرده گزارش شود", url: "https://swift.org/this-page-should-not-exist-xyz", expect: .dead)

// MARK: ۸) عکس‌برداری واقعی صفحه (بستهٔ خواندن و بایگانی)

// WKWebView باید روی رشتهٔ اصلی اجرا شود؛ برای همین حلقهٔ runloop می‌چرخانیم
// تا وظایف MainActor اجرا شوند و تست با بلوکه‌شدن رشتهٔ اصلی قفل نشود.
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
    check("عکس واقعی صفحه گرفته و ذخیره می‌شود",
          FileManager.default.fileExists(atPath: path) && size > 3000,
          "size=\(size)")
    try? FileManager.default.removeItem(atPath: path)
} else {
    check("عکس واقعی صفحه گرفته و ذخیره می‌شود", false, "nil")
}

// MARK: ۹) دستیار هوشمند (درخواست، پرامپت و اتصال زنده)

let aiCfg = AIConfig(baseURL: AIConfig.defaultBaseURL,
                     apiKey: "test-key",
                     model: AIConfig.defaultModel,
                     profile: "")

check("آدرس سرویس: OpenCode Go و نه Zen",
      aiCfg.endpoint?.absoluteString == "https://opencode.ai/zen/go/v1/chat/completions",
      aiCfg.endpoint?.absoluteString ?? "nil")
check("مدل انتخاب‌شده deepseek-v4.1-flash است", aiCfg.model == "deepseek-v4.1-flash")

if let aiReq = AIClient.makeRequest(config: aiCfg, session: "sess-123",
                                    messages: [.user("سلام"), .assistant("درود")]) {
    check("هدر x-opencode-session ارسال می‌شود",
          aiReq.value(forHTTPHeaderField: "x-opencode-session") == "sess-123")
    check("هدر Authorization از نوع Bearer است",
          aiReq.value(forHTTPHeaderField: "Authorization") == "Bearer \("test-key")")
    check("آسیب‌پذیری (User-Agent) شناسایی خودمان است",
          aiReq.value(forHTTPHeaderField: "User-Agent")?.contains("Neshank") == true)
    let bodyText = aiReq.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    check("بدنهٔ درخواست مدل و پیام‌ها را دارد",
          bodyText.contains("deepseek-v4.1-flash") && bodyText.contains("سلام") && bodyText.contains("assistant"),
          String(bodyText.prefix(160)))
    check("روش درخواست POST است", aiReq.httpMethod == "POST")
} else {
    check("ساخت درخواست دستیار", false, "nil")
}

let sysPrompt = AIClient.systemPrompt(
    profile: "طراح رابط کاربری هستم؛ بودجه تا ۲ میلیون",
    title: "مانیتور رنگ‌دقیق دل",
    url: "https://example.com/p/9",
    domain: "example.com",
    note: "برای دفتر خانگی",
    tags: ["خرید", "فناوری"],
    savedAt: "۱ مهر ۱۴۰۵",
    pageContent: "این مانیتور پنل IPS دارد و پوشش رنگی ۹۹٪ sRGB."
)
check("پرامپت شامل آدرس نشانک است", sysPrompt.contains("https://example.com/p/9"))
check("پرامپت شامل پروفایل کاربر است", sysPrompt.contains("طراح رابط کاربری"))
check("پرامپت شامل متن صفحه است", sysPrompt.contains("پنل IPS"))
check("پرامپت شامل یادداشت و برچسب است",
      sysPrompt.contains("برای دفتر خانگی") && sysPrompt.contains("خرید"))
check("پرامپت اگر متن صفحه نبود پیام جایگزین می‌دهد",
      AIClient.systemPrompt(profile: "", title: "t", url: "https://x.io", domain: "x.io",
                            note: "", tags: [], savedAt: "", pageContent: nil)
        .contains("موجود نیست"))
check("بریدن متن بلند رعایت سقف می‌کند",
      AIClient.clip(String(repeating: "الف", count: 5000), 1000).count <= 1000
        && AIClient.clip("کوتاه", 1000) == "کوتاه")

check("پرسش‌های سریع خالی و یکتا نیستند",
      AIClient.QuickAction.all.count >= 5
        && AIClient.QuickAction.all.allSatisfy { !$0.prompt.isBlank && !$0.title.isBlank }
        && Set(AIClient.QuickAction.all.map(\.id)).count == AIClient.QuickAction.all.count)

// اتصال زنده (کلید پیش‌فرض یا کلید ارسالی از محیط)
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
                                               messages: [.user("فقط بنویس: متصل")],
                                               maxTokens: 3000)
        } catch {
            errorAI = String(describing: error)
        }
        semAI.signal()
    }
    _ = semAI.wait(timeout: .now() + 70)
    taskAI.cancel()
    check("اتصال زنده به opencode/go و پاسخ مدل",
          !(answerAI ?? "").isEmpty,
          answerAI.map { String($0.prefix(60)) } ?? (errorAI ?? "nil"))
} else {
    print("ℹ️ تست زندهٔ دستیار — کلید تنظیم نشده؛ رد شد")
}

// MARK: ۱۰) ساخت نشانک نمونه
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

let resinBookmark = makeBookmark(1, "رزین اپوکسی شفاف", "resin-shop.ir",
                                 tags: ["رزین"], note: "برای کامپوزیت")

// منابع پاسخ کتابخانه
check("شمارش منابع پاسخ کتابخانه",
      AIAdvisor.citations([AIAdvisor.ContextItem(bookmark: resinBookmark)]).first?.bookmarkId == 1)
check("پرامپت کتابخانه شمارهٔ منبع می‌گذارد",
      AIAdvisor.libraryUserPrompt(question: "رزین؟",
                                  items: [AIAdvisor.ContextItem(bookmark: resinBookmark)]).contains("[1]"))

// متن چت
check("عنوان خودکار چت کوتاه می‌شود",
      ChatText.autoTitle(String(repeating: "رزین ", count: 40)).count <= 43)
check("پیش‌نمایش پیام تک‌خطی و کوتاه است",
      ChatText.clean("خط اول\nخط دوم", limit: 12).count <= 13)
check("پیام خالی پیش‌نمایش ندارد", ChatText.clean(nil).isEmpty)

// MARK: ۱۱) کیفیت متن و استخراج article (آفلاین)

// سنجش کیفیت: عنوان/منوی تنها قابل‌اعتماد نیست
let titleOnly = PageContentQuality.assess("رزین اپوکسی شفاف | خانه | محصولات | تماس با ما",
                                          title: "رزین اپوکسی شفاف")
check("کیفیت: متنِ فقط‌عنوانی رد می‌شود", !titleOnly.isUsable, titleOnly.explanation)

let articleText = """
رزین اپوکسی شفاف برای قالب‌گیری خانگی انتخاب خوبی است چون زمان پخت کنترل‌پذیری دارد.
ویسکوزیته پایین باعث می‌شود حباب‌های هوا سریع‌تر از مخلوط خارج شوند.
نسبت اختلاط باید دقیق رعایت شود؛ مثلاً دو قسمت رزین و یک قسمت هاردنر.
در دمای اتاق پخت کامل حدود بیست و چهار ساعت طول می‌کشد.
برای پروژه‌های کف، ضخامت لایه نباید از حد مجاز بیشتر شود چون گرمازادهٔ واکنش بالا می‌رود.
""" + "\n" + (1...40).map { "جملهٔ توضیحی شمارهٔ \($0) دربارهٔ فرایند پخت و ایمنی کار با رزین است." }.joined(separator: "\n")
let goodQuality = PageContentQuality.assess(articleText, title: "رزین اپوکسی شفاف")
check("کیفیت: متن مقاله‌ای قابل‌اعتماد است", goodQuality.isUsable, goodQuality.explanation)
check("کیفیت: نرمال‌سازی عربی/نهاده", PageContentQuality.normalize("علي\u{200C}مراد").contains("علی مراد"))

// استخراج از article به‌جای کل صفحهٔ پرسروصدا
let noisyHTML = """
<html><head><title>مقاله</title></head><body>
<nav>خانه | فروشگاه | تماس با ما | ورود کاربران | سبد خرید</nav>
<article><h1>راهنمای پخت رزین</h1><p>\(articleText.split(separator: "\n").prefix(3).joined(separator: " "))</p></article>
<footer>تمام حقوق محفوظ است — خبرنامه — شبکه‌های اجتماعی</footer>
</body></html>
"""
let mainText = HTMLText.extractMain(from: noisyHTML)
check("استخراج: متن article انتخاب می‌شود", mainText.contains("ویسکوزیته پایین"), String(mainText.prefix(80)))
check("استخراج: منوی کناری حذف می‌شود", !mainText.contains("سبد خرید"))

// استخراج اصلی: منو/پابرگِ class-دار و کانتینرهای پرازلینک نباید وارد متن شوند
let divMenuHTML = """
<html><body>
<div class="main-menu"><ul><li><a href="/">خانه</a></li><li><a href="/shop">فروشگاه</a></li><li><a href="/login">ورود</a></li></ul></div>
<div id="content" class="entry-content">
<h1>آموزش لایه‌گذاری فایبرگلاس</h1>
<p>لایه‌گذاری فایبرگلاس یکی از پرکاربردترین روش‌های ساخت قطعات کامپوزیتی است که در آن رزین اپوکسی نقش چسباننده و محافظ را دارد. کیفیت لایه‌گذاری به عوامل متعددی از جمله نسبت اختلاط رزین و هاردنر بستگی دارد، و دمای محیط هم در سخت‌شدن نهایی تأثیر جدی می‌گذارد.</p>
<p>برای شروع، سطح کار را تمیز کنید و لایه‌های پارچه شیشه را با دست کاملاً بچسبانید تا هیچ حباب هوایی باقی نماند؛ سپس رزین را به‌آرامی روی سطح بریزید.</p>
</div>
<div class="site-footer"><p>کلیه حقوق محفوظ است</p><p>درباره ما — تماس — تبلیغات</p></div>
</body></html>
"""
let divMenuText = HTMLText.extractMain(from: divMenuHTML)
check("استخراج: منوی div-محور حذف می‌شود", !divMenuText.contains("فروشگاه") && !divMenuText.contains("ورود"), divMenuText)
check("استخراج: پابرگ class-دار حذف می‌شود", !divMenuText.contains("حقوق محفوظ"), divMenuText)
check("استخراج: متن اصلی حفظ می‌شود", divMenuText.contains("لایه‌گذاری فایبرگلاس"), divMenuText)

let headerNavHTML = """
<html><body>
<header><nav><a href="/a">شبکه‌های اجتماعی</a> <a href="/b">تماس</a> <a href="/c">جستجو</a></nav></header>
<main><p>این متن اصلی مقاله است و چندین جمله دارد تا از آستانهٔ طول عبور کند و به‌عنوان محتوای واقعی شناخته شود. رزین اپوکسی در صنایع مختلف کاربرد دارد و انتخاب نوع مناسب آن به پروژه بستگی کامل دارد.</p><p>پاراگراف دوم برای وزن‌دادن به کاندید اصلی؛ ویسکوزیته پایین نفوذپذیری را بهتر می‌کند و زمان کاری طولانی‌تر امکان دقیق‌تر بودن کار را فراهم می‌سازد.</p></main>
</body></html>
"""
let headerNavText = HTMLText.extractMain(from: headerNavHTML)
check("استخراج: منوی داخل header حذف می‌شود", !headerNavText.contains("شبکه‌های اجتماعی"), headerNavText)
check("استخراج: متن main حفظ می‌شود", headerNavText.contains("ویسکوزیته پایین"), headerNavText)

let linkFarmHTML = """
<html><body>
<div class="links"><a href="/1">رزین اپوکسی</a> <a href="/2">هاردنر</a> <a href="/3">پارچه شیشه</a> <a href="/4">کت</a> <a href="/5">مست</a> <a href="/6">رول</a> <a href="/7">کاتالوگ</a> <a href="/8">قیمت</a> <a href="/9">خرید</a> <a href="/10">فروش</a> <a href="/11">اپوکسی</a> <a href="/12">پلی‌استر</a></div>
<article><p>متن تحلیلی بلند دربارهٔ مقایسهٔ رزین اپوکسی و پلی‌استر که چند جملهٔ کامل دارد و ارزش خواندن؛ ویسکوزیته، زمان ژل‌شدن و استحکام نهایی سه معیار اصلی انتخاب هستند و در ادامه هرکدام را باز می‌کنیم.</p><p>اپوکسی چسبندگی بهتری به فایبرگلاس دارد اما گران‌تر است؛ پلی‌استر سریع‌تر سخت می‌شود ولی بوی بیشتری دارد.</p></article>
</body></html>
"""
let farmText = HTMLText.extractMain(from: linkFarmHTML)
check("استخراج: کانتینر پرازلینک نمی‌برد", farmText.contains("چسبندگی بهتری") && !farmText.contains("کاتالوگ"), farmText)

let fallbackHTML = """
<html><body>
<div class="top-nav"><a href="/">خانه</a><a href="/x">گزارش</a><a href="/y">درباره</a></div>
<p>این یک صفحهٔ ساده بدون ساختار معنایی است اما متن اصلی‌اش ارزش ذخیره دارد و باید بماند.</p>
<p>پاراگراف دوم صفحهٔ ساده؛ استخراج ایستا باید متن را بدون منو برگرداند.</p>
<div class="footer-bar"><a href="/f">حریم خصوصی</a></div>
</body></html>
"""
let fbText = HTMLText.extractMain(from: fallbackHTML)
check("استخراج fallback: متن می‌ماند", fbText.contains("ارزش ذخیره دارد"), fbText)
check("استخراج fallback: منو حذف می‌شود", !fbText.contains("حریم خصوصی") && !fbText.contains("گزارش"), fbText)


// بدنهٔ درخواست: کنترل استدلال (کلید خالی نبودنِ پاسخ در مدل‌های استدلال‌گر)
if let req = AIClient.makeRequest(config: AIConfig(baseURL: AIConfig.defaultBaseURL,
                                                   apiKey: "k",
                                                   model: AIConfig.defaultModel,
                                                   profile: ""),
                                  session: "s",
                                  messages: [.user("سلام")],
                                  maxTokens: 8000,
                                  reasoningEffort: "low"),
   let bodyData = req.httpBody,
   let bodyObj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
    check("درخواست: reasoning_effort در بدنه می‌رود", bodyObj["reasoning_effort"] as? String == "low")
    check("درخواست: سقف توکن در بدنه می‌رود", bodyObj["max_tokens"] as? Int == 8000)
} else {
    check("درخواست: reasoning_effort در بدنه می‌رود", false)
}
if let req = AIClient.makeRequest(config: AIConfig(baseURL: AIConfig.defaultBaseURL,
                                                   apiKey: "k",
                                                   model: AIConfig.defaultModel,
                                                   profile: ""),
                                  session: "s",
                                  messages: [.user("سلام")]),
   let bodyData = req.httpBody,
   let bodyObj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
    check("درخواست: بدون تصریح، فیلد استدلال null می‌ماند",
          bodyObj["reasoning_effort"] is NSNull || bodyObj["reasoning_effort"] == nil)
} else {
    check("درخواست: بدون تصریح، فیلد استدلال null می‌ماند", false)
}

// MARK: ۱۲) خروجی‌های نقشهٔ ذهنی (نام فایل، تم، جهت، HTML/Word)

check("تم: ده تم با برچسب فارسی", MindMapTheme.allCases.count == 10
      && MindMapTheme.allCases.allSatisfy { !$0.label.isBlank })
check("تم: نگاشت تم تیره/روشن", MindMapTheme.forColorScheme(dark: true) == .dark
      && MindMapTheme.forColorScheme(dark: false) == .light)
check("تم: نام‌ها با THEMES سمت JS یکی است",
      Set(MindMapTheme.allCases.map(\.rawValue))
        == ["light", "dark", "forest", "ocean", "sunset", "lavender", "mono", "sand", "sakura", "mint"])
check("چیدمان: پنج چیدمان با برچسب فارسی", MindMapLayout.allCases.count == 5
      && MindMapLayout.allCases.allSatisfy { !$0.label.isBlank && !$0.icon.isBlank })
check("چیدمان: نام‌ها با LAYOUT_NAMES سمت JS یکی است",
      Set(MindMapLayout.allCases.map(\.rawValue)) == ["tree", "org", "radial", "outline", "timeline"])
check("چیدمان: خواندن چیدمان از JSON نقشه",
      MindMapLayout.fromJSON(#"{"meta":{"layout":"radial"},"root":{"id":"root","text":"r","children":[]}}"#) == .radial
      && MindMapLayout.fromJSON(#"{"meta":{},"root":{}}"#) == nil
      && MindMapLayout.fromJSON(#"{"meta":{"layout":"unknown"},"root":{}}"#) == nil)
check("جهت: ریشه چپ مقدار ۱ (RIGHT)", MindMapDirection.rootLeft.rawValue == 1)
check("جهت: ریشه راست مقدار ۰ (LEFT)", MindMapDirection.rootRight.rawValue == 0)

check("نام فایل: نویسه‌های ممنوعه پاک می‌شود",
      MindMapExport.safeFileName("نقشه: رزین/اپوکسی?") == "نقشه- رزین-اپوکسی-")
check("نام فایل: خالی → پیش‌فرض", MindMapExport.safeFileName("   ") == "mindmap")
check("نام فایل: سقف طول", MindMapExport.safeFileName(String(repeating: "ا", count: 200)).count <= 60)

let mdSample = "# تیتر\n\n## زیرتیتر\n\n- آیتم یک\n- آیتم دو\n\nپاراگراف ساده"
let htmlFrag = MindMapExport.markdownToHTML(mdSample)
check("MD→HTML: تیترها", htmlFrag.contains("<h1>تیتر</h1>") && htmlFrag.contains("<h2>زیرتیتر</h2>"))
check("MD→HTML: فهرست", htmlFrag.contains("<ul>") && htmlFrag.contains("<li>آیتم یک</li>"))
check("MD→HTML: پاراگراف", htmlFrag.contains("<p>پاراگراف ساده</p>"))
check("MD→HTML: فرار نویسه‌ها",
      MindMapExport.markdownToHTML("<b>نه</b> & «بله»").contains("&lt;b&gt;نه&lt;/b&gt;"))

let docHTML = MindMapExport.documentHTML(title: "نقشه", markdown: mdSample, sourceURL: "https://x.ir/")
check("سند HTML: عنوان و آدرس و بدنه", docHTML.contains("<title>نقشه</title>")
      && docHTML.contains("https://x.ir/") && docHTML.contains("<h1>تیتر</h1>"))

let fakeIndex = """
<html><head><title>طراحی نقشه ذهنی</title><style>.node{}</style></head><body>
<div id="viewport"></div>
<script>window.renderMindMap=function(){};</script>
</body></html>
"""
let mapJSON = "{\"meta\":{\"title\":\"t\"},\"root\":{\"id\":\"root\",\"text\":\"ریشه\",\"children\":[]}}"
if let standalone = MindMapExport.standaloneHTML(indexHTML: fakeIndex, css: "/*css*/",
                                                 libraryJS: "/*js*/", mapJSON: mapJSON,
                                                 pageTitle: "نقشهٔ من") {
    check("HTML مستقل: داده فقط به صورت JSON.parse و فراخوانی خودکار",
          standalone.contains("renderMindMap(JSON.parse(") && standalone.contains("\\\"meta\\\""))
    check("HTML مستقل: عنوان صفحه", standalone.contains("نقشهٔ من — \(L.tr("Mind Map"))"))
    check("HTML مستقل: بدون ارجاع ریموت", !standalone.contains("src=\"./") && !standalone.contains("href=\"./"))
    check("HTML مستقل: قالب دست‌نخورده می‌ماند", standalone.contains("window.renderMindMap=function(){}"))
} else {
    check("HTML مستقل: ساخته می‌شود", false)
}
check("HTML مستقل: JSON نامعتبر رد می‌شود",
      MindMapExport.standaloneHTML(indexHTML: fakeIndex, css: "", libraryJS: "",
                                   mapJSON: "نه‌جی‌سان", pageTitle: "x") == nil)
let hostileMapJSON = "{\"meta\":{},\"root\":{\"id\":\"root\",\"text\":\"</script><script>alert(1)</script>\",\"children\":[]}}"
let safeStandalone = MindMapExport.standaloneHTML(indexHTML: fakeIndex, css: "", libraryJS: "",
                                                  mapJSON: hostileMapJSON, pageTitle: "x") ?? ""
check("HTML مستقل: محتوای گره نمی‌تواند از script خارج شود",
      !safeStandalone.contains("</script><script>alert(1)") && safeStandalone.contains("\\u003c"))

// MARK: ۱۳) اسکیما و ذخیرهٔ نقشه مستقل از نشانک

let mapRecordJSON = """
{"meta":{"title":"موریس","sourceUrl":"https://fa.wikipedia.org/wiki/موریس",
"createdAt":"2026-09-27T00:00:00Z","model":"deepseek-v4.1-flash","language":"fa"},
"root":{"id":"root","text":"موریس","children":[
  {"id":"n1","text":"جغرافیا","children":[{"id":"n1a","text":"اقیانوس هند","children":[]}]},
  {"id":"n2","text":"تاریخ","children":[]}]}}
"""
if let data = mapRecordJSON.data(using: .utf8),
   let document = try? JSONDecoder().decode(MindMapDocument.self, from: data) {
    check("JSON نقشه: meta و درخت decode می‌شوند", document.meta.title == "موریس" && document.root.children.count == 2)
    check("JSON نقشه: فرزندها مستقل و تودرتو هستند", document.root.children[0].children.first?.text == "اقیانوس هند")
} else {
    check("JSON نقشه: meta و درخت decode می‌شوند", false)
}

let mapRow = DBRow(values: [
    "id": .int(91),
    "title": .text("موریس — جغرافیا"),
    "source_url": .text("https://fa.wikipedia.org/wiki/موریس"),
    "normalized_url": .text("https://fa.wikipedia.org/wiki/موریس"),
    "content_hash": .text("abc123"),
    "mind_map_json": .text(mapRecordJSON),
    "raw_markdown": .text("# موریس\n\n## جغرافیا\n\n## تاریخ"),
    "model": .text("deepseek-v4.1-flash"),
    "language": .text("fa"),
    "created_at": .real(1_790_000_000),
    "updated_at": .real(1_790_000_100)
])
let independentMap = MindMapRecord(row: mapRow)
check("رکورد نقشه: شناسه مستقل از نشانک", independentMap.id == 91 && independentMap.displayNodeCount == 4)
check("رکورد نقشه: آدرس و متن منبع حفظ می‌شوند",
      independentMap.sourceURL.contains("wikipedia.org") && independentMap.rawMarkdown.contains("## جغرافیا"))
check("نصب تازه: هیچ نقشهٔ نمونه‌ای در کد نیست",
      !MindMapAIService.prompt.contains("نقشهٔ نمونه") && !MindMapAIService.prompt.contains("رزین اپوکسی"))

// MARK: نتیجه

print(failures == 0 ? "\n🎉 همهٔ تست‌ها پاس شدند" : "\n❗\(failures) تست ناموفق")
exit(failures == 0 ? 0 : 1)
