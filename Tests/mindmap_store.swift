import Foundation

/// Persistence smoke test against an explicitly injected temporary SQLite database.
/// This test never opens or changes the user's real Application Support database.
///
/// Note: a fresh v1 database is seeded with sample content (4 bookmarks and 4 sample
/// maps by `Library.seedIfNeeded`), so the assertions below expect that seed.
@main
struct MindMapStoreTest {
    @MainActor
    static func main() {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeshankMindMapTest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        let lib = Library(databasePath: testDir.appendingPathComponent("test.sqlite3").path)
        var failures = 0
        func check(_ title: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "✅" : "❌") \(title)\(ok || detail.isEmpty ? "" : " — \(detail)")")
            if !ok { failures += 1 }
        }

        // Fresh install: sample content is seeded on first launch.
        check("fresh install seeds sample bookmarks", lib.counts.all == 4, "bookmarks=\(lib.counts.all)")
        check("fresh install seeds sample mind maps", lib.mindMapCount == 4, "maps=\(lib.mindMapCount)")

        let url = "https://en.wikipedia.org/wiki/Mauritius"
        let jsonA = #"{"meta":{"title":"Mauritius A"},"root":{"id":"root","text":"Mauritius A","children":[{"id":"a","text":"Geography","children":[]}]}}"#
        let jsonB = #"{"meta":{"title":"Mauritius B"},"root":{"id":"root","text":"Mauritius B","children":[{"id":"b","text":"History","children":[]}]}}"#
        let first = lib.createMindMap(title: "Mauritius — Geography", sourceURL: url,
                                      markdown: "# Mauritius\n\n## Geography",
                                      json: jsonA, model: "deepseek-v4.1-flash", language: "en")
        let second = lib.createMindMap(title: "Mauritius — History", sourceURL: url,
                                       markdown: "# Mauritius\n\n## History",
                                       json: jsonB, model: "deepseek-v4.1-flash", language: "en")
        let created = [first?.id, second?.id].compactMap { $0 }
        check("two maps of one URL get independent ids",
              created.count == 2 && created[0] != created[1] && lib.mindMapCount == 6,
              "count=\(lib.mindMapCount)")
        check("each record keeps its own JSON and text",
              first?.mindMapJSON == jsonA && second?.mindMapJSON == jsonB)

        lib.scope = .mindMaps
        let ids = Set(lib.mindMaps.map(\.id))
        check("map list shows every record separately",
              lib.mindMaps.count == 6 && ids.count == 6,
              "list=\(lib.mindMaps.count)")
        if let id = first?.id, let other = second?.id, !created.isEmpty {
            lib.selectedMindMapId = id
            lib.deleteMindMaps(ids: [id])
            check("deleting one map keeps the other",
                  lib.mindMapCount == 5
                    && lib.mindMap(id: other) != nil
                    && lib.mindMaps.count == 5,
                  "list=\(lib.mindMaps.count) counter=\(lib.mindMapCount)")
            check("deleting a map never touches bookmarks",
                  lib.counts.all == 4, "bookmarks=\(lib.counts.all)")
        } else {
            check("deleting one map keeps the other", false)
            check("deleting a map never touches bookmarks", false)
        }
        print(failures == 0 ? "🎉 persistence test passed" : "❗\(failures) persistence tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
