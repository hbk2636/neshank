import Foundation

// MARK: - سلامت لینک

enum LinkChecker {
    enum Health: Sendable {
        case alive
        case dead
        case unknown
    }

    static func check(_ urlString: String) async -> Health {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return .alive }

        // ۱) HEAD
        if let h = await probe(url: url, method: "HEAD") { return h }

        // ۲) GET (بعضی سرورها HEAD را رد می‌کنند)
        if let h = await probe(url: url, method: "GET") { return h }

        return .unknown
    }

    private static func probe(url: URL, method: String) async -> Health? {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 12
        req.setValue(PageMeta.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")

        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse
        else { return nil } // شبکه/تایم‌اوت → نامشخص

        let code = http.statusCode
        switch code {
        case 200..<400:
            return .alive
        case 404, 410, 451:
            return .dead
        case 401, 403, 405, 429, 503, 999:
            // محافظت‌شده/محدود/لوت‌شده توسط ربات → وجود صفحه را نفی نمی‌کنیم
            return .alive
        case 400..<500:
            return .dead
        default:
            return .unknown // خطای سرور ممکن است موقتی باشد
        }
    }
}
