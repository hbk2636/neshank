import Foundation

// MARK: - Data-layer and localization tests
// Run: zsh Scripts/run_tests.sh   (exit 1 = failure; CI-friendly)
// XCTest is unavailable with bare Command Line Tools, so this is a simple harness instead.

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

// Isolated test data — never touches the real user paths
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("neshank-tests-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempDir) }
let testDBPath = tempDir.appendingPathComponent("test.sqlite3").path

// MARK: 1) URL normalization

let stripped = URLNormalizer.url("https://example.com/a?utm_source=x&utm_medium=y&keep=1")?.absoluteString
check("tracking parameters removed", stripped == "https://example.com/a?keep=1", stripped ?? "nil")
check("invalid URL rejected", URLNormalizer.url("not a url") == nil)

// MARK: 2) Digits and localization dictionary

check("Latin digits in English", Digits.fa("42") == "42")

var dictProblems: [String] = []
var seenKeys = Set<String>()
func placeholderCount(_ s: String) -> Int { s.components(separatedBy: "%@").count - 1 }
for e in L10n.core {
    if e.en.isEmpty || e.fa.isEmpty || e.ru.isEmpty || e.zh.isEmpty {
        dictProblems.append("empty field: \(e.en)")
    }
    if !seenKeys.insert(e.en).inserted { dictProblems.append("duplicate key: \(e.en)") }
    if placeholderCount(e.en) != placeholderCount(e.fa) { dictProblems.append("nMismatch fa: \(e.en)") }
    if placeholderCount(e.en) != placeholderCount(e.ru) { dictProblems.append("nMismatch ru: \(e.en)") }
    if placeholderCount(e.en) != placeholderCount(e.zh) { dictProblems.append("nMismatch zh: \(e.en)") }
}
check("localization dictionary healthy (\(L10n.core.count) keys)", dictProblems.isEmpty, dictProblems.prefix(3).joined(separator: " | "))
check("missing key falls back to itself", L.tr("definitely-not-a-key-xyz") == "definitely-not-a-key-xyz")

// MARK: 2.5) UI themes

check("six UI themes defined", UITheme.allCases.count == 6, "\(UITheme.allCases.count)")
check("theme ids unique", Set(UITheme.allCases.map(\.id)).count == 6)
check("classic theme imposes no scheme", UITheme.classic.scheme == nil)
var themeOK = true
for t in UITheme.allCases where t != .classic {
    if t.background == nil || t.windowBaseNS == nil || t.accentColor == nil || t.scheme == nil { themeOK = false }
}
check("non-classic themes have a full palette", themeOK)
check("theme labels are translated", UITheme.allCases.allSatisfy { !$0.label.isEmpty && $0.label != $0.rawValue })

// MARK: 2.6) UI design shells

check("six UI designs defined", UIDesign.allCases.count == 6, "\(UIDesign.allCases.count)")
check("design ids unique", Set(UIDesign.allCases.map(\.id)).count == 6)
check("unknown design falls back to classic", UIDesign(rawValue: "nothing") ?? .classic == .classic)
check("every design has a label and a tagline", UIDesign.allCases.allSatisfy { !$0.label.isEmpty && !$0.tagline.isEmpty })
check("design labels are translated", UIDesign.allCases.allSatisfy { $0.label != $0.rawValue })

// MARK: 2.7) Video downloader engine (yt-dlp)

check("progress percent parsed", YtDlp.progressPercent(from: "[download]  42.3% of ~ 10.00MiB") == 42.3)
check("progress 100% parsed", YtDlp.progressPercent(from: "[download] 100% of 5MiB") == 100)
check("non-progress line ignored", YtDlp.progressPercent(from: "[ExtractAudio] Destination done") == nil)

let audioArgs = YtDlp.arguments(mode: .audio, url: "https://youtu.be/x",
                                destination: URL(fileURLWithPath: "/tmp/d"), hasFFmpeg: false)
check("audio without ffmpeg has no merge flag", !audioArgs.contains("--merge-output-format"))
check("audio without ffmpeg selects the m4a stream", audioArgs.contains("ba[ext=m4a]/ba"))
check("URL is the last argument", audioArgs.last == "https://youtu.be/x")
check("output template present in args", audioArgs.contains { $0.contains("/tmp/d/%(title)s.%(ext)s") })

let videoArgs = YtDlp.arguments(mode: .video720, url: "https://youtu.be/x",
                                destination: URL(fileURLWithPath: "/tmp/d"), hasFFmpeg: true)
check("video with ffmpeg merges to mp4", videoArgs.contains("--merge-output-format") && videoArgs.contains("mp4"))
check("720p cap present in video args", videoArgs.contains { $0.contains("height<=720") })

let metaJSON = #"{"title":"Test video","uploader":"Test channel","duration":125.4,"webpage_url":"https://youtu.be/x"}"#
let meta = try? JSONDecoder().decode(YtDlp.VideoMetadata.self, from: Data(metaJSON.utf8))
check("video metadata decoded", meta?.title == "Test video" && meta?.uploader == "Test channel")
check("duration format", YtDlp.durationText(125.4) == "2:05" && YtDlp.durationText(3725) == "1:02:05")
check("invalid duration becomes nil", YtDlp.durationText(0) == nil)

let detail = YtDlp.parseProgressDetail(from: "[download]  42.3% of ~ 10.20MiB at  1.50MiB/s ETA 00:05")
check("total size parsed", detail.total == "10.20MiB", detail.total ?? "nil")
check("speed parsed", detail.speed == "1.50MiB/s", detail.speed ?? "nil")
check("ETA parsed", detail.eta == "00:05", detail.eta ?? "nil")
let noDetail = YtDlp.parseProgressDetail(from: "[Merger] Merging formats")
check("non-download line has no details", noDetail.total == nil && noDetail.speed == nil && noDetail.eta == nil)
check("file size format", YtDlp.fileSizeText(302_000) == "295K" && YtDlp.fileSizeText(9_800_000) == "9.3M")
check("clock format", YtDlp.clockText(5) == "5" && YtDlp.clockText(65) == "1:05")
check("video source detection", VideoSource.detect("https://www.youtube.com/watch?v=x") == .youtube
    && VideoSource.detect("https://www.aparat.com/v/abc") == .aparat
    && VideoSource.detect("https://example.com/f.mp4") == .direct)
check("Aparat video id extracted", AparatBackend.videoID(from: "https://www.aparat.com/v/c2d5q8n/") == "c2d5q8n")

if FileManager.default.isExecutableFile(atPath: "/tmp/yt-dlp-macos") {
    check("binary resolved from the environment variable",
          YtDlp.binaryURL(environment: ["NESHANKYAR_YTDLP": "/tmp/yt-dlp-macos"])?.path == "/tmp/yt-dlp-macos")
}
check("missing binary returns nil",
      YtDlp.binaryURL(bundle: .main,
                      environment: ["NESHANKYAR_YTDLP": "/nonexistent/yt-dlp"],
                      toolsDirectory: URL(fileURLWithPath: "/nonexistent/tools")) == nil)

// MARK: 3) Database opens cleanly + migration

let lib = Library(databasePath: testDBPath)
check("database opens without storageError", lib.storageError == nil, lib.storageError ?? "")

do {
    let db = try Database(path: testDBPath)
    let version = try db.scalarInt("PRAGMA user_version")
    check("schema migration recorded as version 2", version == 2, "user_version=\(version ?? -1)")
    let cols = try db.rows("PRAGMA table_info(mind_maps)")
    check("node_count column exists", cols.contains { $0.text("name") == "node_count" })
} catch {
    check("schema inspection", false, "\(error)")
}

// MARK: 4) mind-map node_count

let mapJSON = """
{"meta":{"title":"t"},"root":{"id":"root","text":"r","children":[
 {"id":"a","text":"a","children":[]},{"id":"b","text":"b","children":[]}]}}
"""
if let record = lib.createMindMap(title: "Map", sourceURL: "https://example.com/x",
                                  markdown: "md", json: mapJSON, model: "m", language: "en") {
    do {
        let db = try Database(path: testDBPath)
        let stored = try db.scalarInt("SELECT node_count FROM mind_maps WHERE id = ?", [.int(record.id)])
        check("insert stores node_count=3", stored == 3, "stored=\(stored ?? -1)")
    } catch { check("read node_count", false, "\(error)") }

    lib.scope = .mindMaps
    // the seed also inserts sample maps — the count must account for the test's own record
    let listed = lib.mindMaps.first(where: { $0.id == record.id })
    check("list renders the count without parsing JSON", listed?.displayNodeCount == 3,
          "\(listed?.displayNodeCount ?? -1)")
    check("full JSON readable on demand", lib.mindMap(id: record.id)?.mindMapJSON.isEmpty == false)

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
        check("update stores node_count=4", updated && stored == 4, "stored=\(stored ?? -1)")
    } catch { check("read node_count after edit", false, "\(error)") }
} else {
    check("create mind map record", false, "record nil")
}

// MARK: 5) Backups

// the seed inserts four sample bookmarks — clear the table for the snapshot test
try? Database(path: testDBPath).run("DELETE FROM bookmarks")
await lib.add(rawURL: "https://example.com/b1", title: "B1", note: "", folderId: nil,
              tags: [], fetchMeta: false)
do {
    let backupURL = try Database.backup(sourcePath: testDBPath,
                                        directory: tempDir.appendingPathComponent("bk").path,
                                        prefix: "auto")
    check("backup file created", FileManager.default.fileExists(atPath: backupURL.path))
    let restored = try Database(path: backupURL.path)
    let count = try restored.scalarInt("SELECT COUNT(*) FROM bookmarks")
    check("snapshot contains the data", count == 1, "count=\(count ?? -1)")
} catch {
    check("run backup", false, "\(error)")
}

do {
    _ = try Database.backup(sourcePath: tempDir.appendingPathComponent("missing.sqlite3").path,
                            directory: tempDir.path, prefix: "auto")
    check("backup from a missing source fails", false, "should not have succeeded")
} catch {
    check("backup from a missing source fails", true)
}

do {
    let backupsDir = tempDir.appendingPathComponent("backups").path
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "lastAutoBackup")
    Library.dailyBackupIfNeeded(sourcePath: testDBPath, backupsDirectory: backupsDir, keep: 3)
    var files = try FileManager.default.contentsOfDirectory(atPath: backupsDir)
    check("daily backup runs on first call", files.count == 1, "n=\(files.count)")
    Library.dailyBackupIfNeeded(sourcePath: testDBPath, backupsDirectory: backupsDir, keep: 3)
    files = try FileManager.default.contentsOfDirectory(atPath: backupsDir)
    check("no second backup on the same day", files.count == 1, "n=\(files.count)")
    for i in 0..<6 {
        defaults.removeObject(forKey: "lastAutoBackup")
        let day = Calendar.current.date(byAdding: .day, value: -10 + i, to: Date())!
        _ = try Database.backup(sourcePath: testDBPath, directory: backupsDir,
                                prefix: "auto", stamp: day)
        Library.pruneBackups(directory: backupsDir, prefix: "neshank-auto-", keep: 3)
    }
    files = try FileManager.default.contentsOfDirectory(atPath: backupsDir)
    check("prune keeps at most 3 copies", files.count == 3, "n=\(files.count)")
    defaults.removeObject(forKey: "lastAutoBackup")
} catch {
    check("daily backup logic", false, "\(error)")
}

// MARK: 6) Two-sided mind-map layout (reference screenshot style)

do {
    // enum and canvas names must match, otherwise the menu item is a no-op
    check("mindmap layout exists in enum", MindMapLayout.mindmap.rawValue == "mindmap")
    check("menu exposes six layouts", MindMapLayout.allCases.count == 6, "\(MindMapLayout.allCases.count)")
    check("mindMap layout has a label", !MindMapLayout.mindmap.label.isEmpty)
    let canvasPath = "Sources/NeshankYar/Resources/MindMap/canvas.html"
    let canvas = try String(contentsOfFile: canvasPath, encoding: .utf8)
    check("canvas knows the mindmap layout", canvas.contains("'mindmap'"))
    check("canvas has the balanced layout function", canvas.contains("function layoutBalanced()"))
    check("canvas draws opposing links", canvas.contains("anchor(p, true, n)"))
    check("outline aligns the left edge", canvas.contains("n.x = depth * INDENT + n.w / 2"))
    check("outline uses vertical connectors", canvas.contains("layoutName === 'outline'"))
} catch {
    check("read canvas for layout checks", false, "\(error)")
}

// MARK: Summary

print("――― \(passed) passed, \(failures) failed ―――")
exit(failures == 0 ? 0 : 1)
