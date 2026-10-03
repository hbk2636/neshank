import Foundation

// MARK: - تست‌های لایهٔ داده و بومی‌سازی
// اجرا: swift run neshank-test   (خروج ۱ = شکست؛ مناسب CI)
// XCTest با CommandLineTools در دسترس نیست؛ به‌جایش یک هارنس ساده.

setbuf(stdout, nil)
nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var passed = 0
func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond {
        passed += 1
        print("✅ \(name)")
    } else {
        failures += 1
        print("❌ \(name)  \(detail)")
    }
}

// دیتای تست ایزوله — هرگز به مسیر واقعی کاربر دست نمی‌زند
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("neshank-tests-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempDir) }
let testDBPath = tempDir.appendingPathComponent("test.sqlite3").path

// MARK: ۱) نرمال‌سازی آدرس

let stripped = URLNormalizer.url("https://example.com/a?utm_source=x&utm_medium=y&keep=1")?.absoluteString
check("حذف پارامترهای ردیابی", stripped == "https://example.com/a?keep=1", stripped ?? "nil")
check("رد آدرس نامعتبر", URLNormalizer.url("not a url") == nil)

// MARK: ۲) ارقام و دیکشنری بومی‌سازی

check("ارقام لاتین در زبان انگلیسی", Digits.fa("42") == "42")

var dictProblems: [String] = []
var seenKeys = Set<String>()
func placeholderCount(_ s: String) -> Int { s.components(separatedBy: "%@").count - 1 }
for e in L10n.core {
    if e.en.isEmpty || e.fa.isEmpty || e.ru.isEmpty || e.zh.isEmpty {
        dictProblems.append("فیلد خالی: \(e.en)")
    }
    if !seenKeys.insert(e.en).inserted { dictProblems.append("کلید تکراری: \(e.en)") }
    if placeholderCount(e.en) != placeholderCount(e.fa) { dictProblems.append("nMismatch fa: \(e.en)") }
    if placeholderCount(e.en) != placeholderCount(e.ru) { dictProblems.append("nMismatch ru: \(e.en)") }
    if placeholderCount(e.en) != placeholderCount(e.zh) { dictProblems.append("nMismatch zh: \(e.en)") }
}
check("دیکشنری بومی‌سازی سالم (\(L10n.core.count) کلید)", dictProblems.isEmpty, dictProblems.prefix(3).joined(separator: " | "))
check("fallback به انگلیسی", L.tr("definitely-not-a-key-xyz") == "definitely-not-a-key-xyz")

// MARK: ۲.۵) تمپلیت‌های ظاهری

check("۶ تمپلیت تعریف شده", UITheme.allCases.count == 6, "\(UITheme.allCases.count)")
check("شناسه‌های تم یکتا", Set(UITheme.allCases.map(\.id)).count == 6)
check("کلاسیک بدون تحمیل اسکیم", UITheme.classic.scheme == nil)
var themeOK = true
for t in UITheme.allCases where t != .classic {
    if t.background == nil || t.windowBaseNS == nil || t.accentColor == nil || t.scheme == nil { themeOK = false }
}
check("تم‌های غیر کلاسیک پالت کامل دارند", themeOK)
check("برچسب تم‌ها ترجمه دارند", UITheme.allCases.allSatisfy { !$0.label.isEmpty && $0.label != $0.rawValue })

// MARK: ۲.۶) طراحی‌های رابط (چیدمان‌ها)

check("۶ طراحی رابط تعریف شده", UIDesign.allCases.count == 6, "\(UIDesign.allCases.count)")
check("شناسه‌های طراحی یکتا", Set(UIDesign.allCases.map(\.id)).count == 6)
check("پیش‌فرض چیدمان کلاسیک است", UIDesign(rawValue: "nothing") ?? .classic == .classic)
check("هر طراحی برچسب و توضیح دارد", UIDesign.allCases.allSatisfy { !$0.label.isEmpty && !$0.tagline.isEmpty })
check("برچسب طراحی‌ها ترجمه دارند", UIDesign.allCases.allSatisfy { $0.label != $0.rawValue })

// MARK: ۲.۷) ابزار دانلود ویدیو (yt-dlp)

check("پارس درصد پیشرفت", YtDlp.progressPercent(from: "[download]  42.3% of ~ 10.00MiB") == 42.3)
check("پارس درصد ۱۰۰", YtDlp.progressPercent(from: "[download] 100% of 5MiB") == 100)
check("خط بدون پیشرفت نادیده گرفته می‌شود", YtDlp.progressPercent(from: "[ExtractAudio] Destination done") == nil)

let audioArgs = YtDlp.arguments(mode: .audio, url: "https://youtu.be/x",
                                destination: URL(fileURLWithPath: "/tmp/d"), hasFFmpeg: false)
check("صدای بدون ffmpeg ادغام ندارد", !audioArgs.contains("--merge-output-format"))
check("صدای بدون ffmpeg جریان m4a می‌گیرد", audioArgs.contains("ba[ext=m4a]/ba"))
check("URL آخرین آرگومان است", audioArgs.last == "https://youtu.be/x")
check("قالب مقصد در آرگومان‌ها هست", audioArgs.contains { $0.contains("/tmp/d/%(title)s.%(ext)s") })

let videoArgs = YtDlp.arguments(mode: .video720, url: "https://youtu.be/x",
                                destination: URL(fileURLWithPath: "/tmp/d"), hasFFmpeg: true)
check("ویدیوی با ffmpeg ادغام mp4", videoArgs.contains("--merge-output-format") && videoArgs.contains("mp4"))
check("سقف ۷۲۰ در آرگومان ویدیو", videoArgs.contains { $0.contains("height<=720") })

let metaJSON = #"{"title":"تست ویدیو","uploader":"کانال آزمایشی","duration":125.4,"webpage_url":"https://youtu.be/x"}"#
let meta = try? JSONDecoder().decode(YtDlp.VideoMetadata.self, from: Data(metaJSON.utf8))
check("دیکود متادیتای ویدیو", meta?.title == "تست ویدیو" && meta?.uploader == "کانال آزمایشی")
check("قالب مدت زمان", YtDlp.durationText(125.4) == "2:05" && YtDlp.durationText(3725) == "1:02:05")
check("مدت نامعتبر nil می‌شود", YtDlp.durationText(0) == nil)

let detail = YtDlp.parseProgressDetail(from: "[download]  42.3% of ~ 10.20MiB at  1.50MiB/s ETA 00:05")
check("پارس حجم کل", detail.total == "10.20MiB", detail.total ?? "nil")
check("پارس سرعت", detail.speed == "1.50MiB/s", detail.speed ?? "nil")
check("پارس زمان باقی‌مانده", detail.eta == "00:05", detail.eta ?? "nil")
let noDetail = YtDlp.parseProgressDetail(from: "[Merger] Merging formats")
check("خط غیر دانلود جزئیات ندارد", noDetail.total == nil && noDetail.speed == nil && noDetail.eta == nil)
check("قالب حجم", YtDlp.fileSizeText(302_000) == "295K" && YtDlp.fileSizeText(9_800_000) == "9.3M")
check("قالب ساعت‌شمار", YtDlp.clockText(5) == "5" && YtDlp.clockText(65) == "1:05")
check("تشخیص منبع ویدیو", VideoSource.detect("https://www.youtube.com/watch?v=x") == .youtube
    && VideoSource.detect("https://www.aparat.com/v/abc") == .aparat
    && VideoSource.detect("https://example.com/f.mp4") == .direct)
check("شناسهٔ آپارات", AparatBackend.videoID(from: "https://www.aparat.com/v/c2d5q8n/") == "c2d5q8n")

if FileManager.default.isExecutableFile(atPath: "/tmp/yt-dlp-macos") {
    check("باینری از متغیر محیطی خوانده می‌شود",
          YtDlp.binaryURL(environment: ["NESHANKYAR_YTDLP": "/tmp/yt-dlp-macos"])?.path == "/tmp/yt-dlp-macos")
}
check("باینری ناموجود nil می‌دهد",
      YtDlp.binaryURL(bundle: .main,
                      environment: ["NESHANKYAR_YTDLP": "/nonexistent/yt-dlp"],
                      toolsDirectory: URL(fileURLWithPath: "/nonexistent/tools")) == nil)

// MARK: ۳) دیتابیس: باز شدن بدون خطا + مهاجرت

let lib = Library(databasePath: testDBPath)
check("باز شدن دیتابیس بدون storageError", lib.storageError == nil, lib.storageError ?? "")

do {
    let db = try Database(path: testDBPath)
    let version = try db.scalarInt("PRAGMA user_version")
    check("مهاجرت نسخهٔ ۲ ثبت شده", version == 2, "user_version=\(version ?? -1)")
    let cols = try db.rows("PRAGMA table_info(mind_maps)")
    check("ستون node_count موجود است", cols.contains { $0.text("name") == "node_count" })
} catch {
    check("بازرسی اسکیما", false, "\(error)")
}

// MARK: ۴) node_count نقشهٔ ذهنی

let mapJSON = """
{"meta":{"title":"t"},"root":{"id":"root","text":"r","children":[
 {"id":"a","text":"a","children":[]},{"id":"b","text":"b","children":[]}]}}
"""
if let record = lib.createMindMap(title: "Map", sourceURL: "https://example.com/x",
                                  markdown: "md", json: mapJSON, model: "m", language: "en") {
    do {
        let db = try Database(path: testDBPath)
        let stored = try db.scalarInt("SELECT node_count FROM mind_maps WHERE id = ?", [.int(record.id)])
        check("درج node_count=3", stored == 3, "stored=\(stored ?? -1)")
    } catch { check("خواندن node_count", false, "\(error)") }

    lib.scope = .mindMaps
    // seed دو نقشهٔ نمونه هم درج می‌کند — شمارش باید رکورد خودِ تست را بگیرد
    let listed = lib.mindMaps.first(where: { $0.id == record.id })
    check("فهرست بدون JSON شمارش درست می‌دهد", listed?.displayNodeCount == 3,
          "\(listed?.displayNodeCount ?? -1)")
    check("خواندن کامل JSON دارد", lib.mindMap(id: record.id)?.mindMapJSON.isEmpty == false)

    let bigger = """
    {"meta":{"title":"t"},"root":{"id":"root","text":"r","children":[
     {"id":"a","text":"a","children":[]},{"id":"b","text":"b","children":[]},
     {"id":"c","text":"c","children":[]}]}}
    """
    let updated = lib.updateMindMap(id: record.id, title: "Map", sourceURL: "https://example.com/x",
                                    markdown: "md", json: bigger, model: "m", language: "en")
    do {
        let db = try Database(path: testDBPath)
        let stored = try db.scalarInt("SELECT node_count FROM mind_maps WHERE id = ?", [.int(record.id)])
        check("به‌روزرسانی node_count=4", updated && stored == 4, "stored=\(stored ?? -1)")
    } catch { check("خواندن node_count پس از ویرایش", false, "\(error)") }
} else {
    check("ساخت نقشهٔ ذهنی", false, "record nil")
}

// MARK: ۵) بک‌آپ

// seed چهار بوکمارک نمونه درج می‌کند — برای تست اسنپ‌شات، جدول خالی می‌شود
try? Database(path: testDBPath).run("DELETE FROM bookmarks")
await lib.add(rawURL: "https://example.com/b1", title: "B1", note: "", folderId: nil,
              tags: [], fetchMeta: false)
do {
    let backupURL = try Database.backup(sourcePath: testDBPath,
                                        directory: tempDir.appendingPathComponent("bk").path,
                                        prefix: "auto")
    check("فایل بک‌آپ ساخته شد", FileManager.default.fileExists(atPath: backupURL.path))
    let restored = try Database(path: backupURL.path)
    let count = try restored.scalarInt("SELECT COUNT(*) FROM bookmarks")
    check("اسنپ‌شات داده را دارد", count == 1, "count=\(count ?? -1)")
} catch {
    check("بک‌آپ‌گیری", false, "\(error)")
}

do {
    _ = try Database.backup(sourcePath: tempDir.appendingPathComponent("missing.sqlite3").path,
                            directory: tempDir.path, prefix: "auto")
    check("بک‌آپ از منبع ناموجود شکست می‌خورد", false, "نباید موفق می‌شد")
} catch {
    check("بک‌آپ از منبع ناموجود شکست می‌خورد", true)
}

do {
    let backupsDir = tempDir.appendingPathComponent("backups").path
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "lastAutoBackup")
    Library.dailyBackupIfNeeded(sourcePath: testDBPath, backupsDirectory: backupsDir, keep: 3)
    var files = try FileManager.default.contentsOfDirectory(atPath: backupsDir)
    check("بک‌آپ روزانه اول اجرا شد", files.count == 1, "n=\(files.count)")
    Library.dailyBackupIfNeeded(sourcePath: testDBPath, backupsDirectory: backupsDir, keep: 3)
    files = try FileManager.default.contentsOfDirectory(atPath: backupsDir)
    check("همان روز دوباره بک‌آپ نمی‌گیرد", files.count == 1, "n=\(files.count)")
    for i in 0..<6 {
        defaults.removeObject(forKey: "lastAutoBackup")
        let day = Calendar.current.date(byAdding: .day, value: -10 + i, to: Date())!
        _ = try Database.backup(sourcePath: testDBPath, directory: backupsDir,
                                prefix: "auto", stamp: day)
        Library.pruneBackups(directory: backupsDir, prefix: "neshank-auto-", keep: 3)
    }
    files = try FileManager.default.contentsOfDirectory(atPath: backupsDir)
    check("هرس به سقف ۳ نسخه", files.count == 3, "n=\(files.count)")
    defaults.removeObject(forKey: "lastAutoBackup")
} catch {
    check("منطق بک‌آپ روزانه", false, "\(error)")
}

// MARK: ۶) چیدمان دوطرفهٔ نقشهٔ ذهنی (سبک تصویر مرجع)

do {
    // enum و بوم باید هم‌نام باشند، وگرنه آیتم منو بی‌اثر می‌شود
    check("چیدمان mindmap در enum هست", MindMapLayout.mindmap.rawValue == "mindmap")
    check("منو شش چیدمان دارد", MindMapLayout.allCases.count == 6, "\(MindMapLayout.allCases.count)")
    check("برچسب mindmap خالی نیست", !MindMapLayout.mindmap.label.isEmpty)
    let canvasPath = "Sources/NeshankYar/Resources/MindMap/canvas.html"
    let canvas = try String(contentsOfFile: canvasPath, encoding: .utf8)
    check("بوم mindmap را می‌شناسد", canvas.contains("'mindmap'"))
    check("بوم تابع چیدمان متوازن دارد", canvas.contains("function layoutBalanced()"))
    check("بوم سیم روبه‌رو دارد", canvas.contains("anchor(p, true, n)"))
    check("اوت‌لاین لبهٔ چپ هم‌تراز دارد", canvas.contains("n.x = depth * INDENT + n.w / 2"))
    check("اوت‌لاین اتصال عمودی دارد", canvas.contains("layoutName === 'outline'"))
} catch {
    check("خواندن بوم برای چیدمان", false, "\(error)")
}

// MARK: جمع‌بندی

print("――― \(passed) موفق، \(failures) شکست ―――")
exit(failures == 0 ? 0 : 1)
