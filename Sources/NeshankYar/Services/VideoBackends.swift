import Foundation

// MARK: - بک‌اندهای دانلود ویدیو: تشخیص سرویس از روی URL

enum VideoSource {
    case aparat
    case youtube
    case direct       // لینک مستقیم رسانه (mp4/m4a/…)

    static func detect(_ urlString: String) -> VideoSource {
        let lowered = urlString.lowercased()
        if lowered.contains("aparat.com") { return .aparat }
        if lowered.contains("youtube.com") || lowered.contains("youtu.be") { return .youtube }
        return .direct
    }
}

// MARK: - آپارات: API عمومی، لینک مستقیم، بدون دیوار ضدهربات

struct AparatVideo: Codable, Equatable {
    let title: String?
    let username: String?
    let duration: Int?
    let bigPoster: String?
    let fileLink: String?

    enum CodingKeys: String, CodingKey {
        case title, username, duration
        case bigPoster = "big_poster"
        case fileLink = "file_link"
    }
}

enum AparatBackend {

    /// شناسهٔ ویدیو از لینک: aparat.com/v/HASH یا aparat.com/v/HASH/… 
    static func videoID(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              url.host()?.contains("aparat.com") == true else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        if parts.first == "v", parts.count > 1 { return parts[1] }
        return nil
    }

    static func apiURL(for id: String) -> URL? {
        URL(string: "https://www.aparat.com/etc/api/video/videohash/\(id)")
    }

    /// واکشی متادیتا + لینک مستقیم ۷۲۰p
    static func fetchVideo(id: String) async throws -> AparatVideo {
        guard let apiURL = apiURL(for: id) else { throw YtDlp.ToolError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        let decoded = try JSONDecoder().decode(AparatAPIResponse.self, from: data)
        guard let video = decoded.video, !(video.fileLink ?? "").isEmpty else {
            throw YtDlp.ToolError.invalidURL
        }
        return video
    }

    private struct AparatAPIResponse: Codable {
        let video: AparatVideo?
    }
}

// MARK: دانلود با پیشرفت (URLSession download delegate)

enum DownloadError: LocalizedError {
    case badStatus(Int)
    case moveFailed(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return L.tf("The server refused the download (HTTP %@).", "\(code)")
        case .moveFailed(let detail):
            return L.tf("The file could not be saved: %@", detail)
        }
    }
}

/// پیشرفت و پایان دانلود.
///
/// نکتهٔ کلیدی: فایل موقتِ `location` فقط تا **بازگشتِ همین متد** زنده است؛
/// به‌محض بازگشت، URLSession آن را حذف می‌کند. پس انتقال به مقصد باید
/// **همزمان** همین‌جا انجام شود — اگر به یک `Task` غیرهمزمان سپرده شود،
/// `moveItem` با «فایل وجود ندارد» شکست می‌خورد و اگر خطا بلعیده شود،
/// دانلود برای همیشه روی ۹۹٪ می‌ماند.
final class ProgressDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: (Double) -> Void
    private let onFinish: (Result<URL, Error>) -> Void
    private let onBytes: ((Int64, Int64) -> Void)?
    private var finished = false

    init(destination: URL,
         onProgress: @escaping (Double) -> Void,
         onBytes: ((Int64, Int64) -> Void)? = nil,
         onFinish: @escaping (Result<URL, Error>) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        self.onBytes = onBytes
        self.onFinish = onFinish
    }

    /// فقط یک‌بار گزارش پایان بده (هم `didFinish` و هم `didComplete` ممکن است بیایند)
    private func complete(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        onFinish(result)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            onProgress(min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }
        onBytes?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // خطاهای HTTP در URLSession «خطا» محسوب نمی‌شوند — باید خودمان بگیریم
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            complete(.failure(DownloadError.badStatus(http.statusCode)))
            return
        }
        // انتقالِ همزمان، پیش از بازگشت از این متد
        do {
            let fm = FileManager.default
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: location, to: destination)
            complete(.success(destination))
        } catch {
            complete(.failure(DownloadError.moveFailed(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { complete(.failure(error)) }
    }
}
