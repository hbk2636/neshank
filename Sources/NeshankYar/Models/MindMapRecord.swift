import Foundation

/// نقشهٔ ذهنی یک موجودیت مستقل از نشانک است.
/// هر بار تولید، یک ردیف جدید می‌سازد؛ URL تکراری نقشهٔ قبلی را بازنویسی نمی‌کند.
struct MindMapRecord: Identifiable, Hashable {
    var id: Int64
    var title: String
    var sourceURL: String
    var normalizedURL: String
    var contentHash: String
    var mindMapJSON: String
    var rawMarkdown: String
    var model: String
    var language: String
    var nodeCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(row: DBRow) {
        id = row.int("id") ?? 0
        title = row.textOrEmpty("title")
        sourceURL = row.textOrEmpty("source_url")
        normalizedURL = row.textOrEmpty("normalized_url")
        contentHash = row.textOrEmpty("content_hash")
        mindMapJSON = row.textOrEmpty("mind_map_json")
        rawMarkdown = row.textOrEmpty("raw_markdown")
        model = row.textOrEmpty("model")
        language = row.textOrEmpty("language")
        nodeCount = Int(row.int("node_count") ?? 0)
        createdAt = Date(timeIntervalSince1970: row.double("created_at") ?? 0)
        updatedAt = Date(timeIntervalSince1970: row.double("updated_at") ?? 0)
    }

    var displayTitle: String { title.trimmed.isEmpty ? sourceURL : title.trimmed }
    var domain: String { URLNormalizer.domain(ofString: sourceURL) }

    /// شمارش گره برای نمایش: ستون ذخیره‌شده اصل است؛ اگر صفر بود ولی JSON موجود است
    /// (مثلاً رکورد تازه پیش از نوشتن)، از روی JSON شمرده می‌شود.
    var displayNodeCount: Int {
        nodeCount > 0 ? nodeCount : Self.countNodes(in: mindMapJSON)
    }

    /// شمارش گره‌ها از روی JSON — برای بک‌فیل مهاجرت و fallback
    static func countNodes(in json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = object["root"] as? [String: Any] else { return 0 }
        var count = 0
        var pending: [[String: Any]] = [root]
        while let node = pending.popLast() {
            count += 1
            pending.append(contentsOf: (node["children"] as? [[String: Any]]) ?? [])
        }
        return count
    }
}
