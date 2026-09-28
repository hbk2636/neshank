import Foundation

/// Persistence smoke test against an explicitly injected temporary SQLite database.
/// This test never opens or changes the user's real Application Support database.
@main
struct MindMapStoreTest {
    @MainActor
    static func main() {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeshankMindMapTest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        let lib = Library(databasePath: testDir.appendingPathComponent("test.sqlite3").path)
        var failures = 0
        func check(_ title: String, _ ok: Bool) {
            print("\(ok ? "✅" : "❌") \(title)")
            if !ok { failures += 1 }
        }

        check("نصب تازه هیچ نقشهٔ نمونه ندارد", lib.mindMapCount == 0 && lib.mindMaps.isEmpty)
        check("نصب تازه هیچ نشانکی ندارد", lib.counts.all == 0)

        let url = "https://fa.wikipedia.org/wiki/موریس"
        let jsonA = #"{"meta":{"title":"موریس A"},"root":{"id":"root","text":"موریس A","children":[{"id":"a","text":"جغرافیا","children":[]}]}}"#
        let jsonB = #"{"meta":{"title":"موریس B"},"root":{"id":"root","text":"موریس B","children":[{"id":"b","text":"تاریخ","children":[]}]}}"#
        let first = lib.createMindMap(title: "موریس — جغرافیا", sourceURL: url,
                                      markdown: "# موریس\n\n## جغرافیا",
                                      json: jsonA, model: "deepseek-v4.1-flash", language: "fa")
        let second = lib.createMindMap(title: "موریس — تاریخ", sourceURL: url,
                                       markdown: "# موریس\n\n## تاریخ",
                                       json: jsonB, model: "deepseek-v4.1-flash", language: "fa")
        check("دو نقشهٔ یک URL دو شناسهٔ مستقل می‌گیرند",
              first != nil && second != nil && first?.id != second?.id && lib.mindMapCount == 2)
        check("هر رکورد JSON و متن خودش را نگه می‌دارد",
              first?.mindMapJSON == jsonA && second?.mindMapJSON == jsonB)

        lib.scope = .mindMaps
        check("فهرست اصلیِ نقشه‌ها هر دو رکورد را جدا نشان می‌دهد",
              lib.mindMaps.count == 2 && Set(lib.mindMaps.map(\.id)).count == 2)
        if let id = first?.id {
            lib.selectedMindMapId = id
            lib.deleteMindMaps(ids: [id])
            check("حذف یک نقشه، نقشهٔ دیگر را نگه می‌دارد", lib.mindMaps.count == 1)
            check("حذف نقشه به نشانک‌ها دست نمی‌زند", lib.counts.all == 0)
        } else {
            check("حذف یک نقشه، نقشهٔ دیگر را نگه می‌دارد", false)
            check("حذف نقشه به نشانک‌ها دست نمی‌زند", false)
        }
        print(failures == 0 ? "🎉 persistence test passed" : "❗\(failures) persistence tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
