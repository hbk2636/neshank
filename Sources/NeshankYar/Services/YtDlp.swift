import Foundation

// MARK: - پوشش yt-dlp: مسیر باینری، ساخت آرگومان‌ها، پارس خروجی

/// توابع خالص این enum در تست‌ها (NeshankTest) پوشش داده می‌شوند.
enum YtDlp {

    enum ToolError: LocalizedError {
        case binaryNotFound
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .binaryNotFound: return L.tr("The yt-dlp tool was not found inside the app.")
            case .invalidURL: return L.tr("This address is not a valid video link.")
            }
        }
    }

    enum OutputMode: String, CaseIterable, Identifiable {
        case audio      // صدای M4A — بدون نیاز به ffmpeg
        case video720   // ویدیو تا ۷۲۰p — با ffmpeg ادغام می‌شود

        var id: String { rawValue }

        var label: String {
            switch self {
            case .audio: return L.tr("Audio (M4A)")
            case .video720: return L.tr("Video (720p)")
            }
        }
    }

    struct VideoMetadata: Codable, Equatable {
        let title: String?
        let uploader: String?
        let duration: Double?
        let thumbnail: String?
        let description: String?
        let webpageURL: String?

        enum CodingKeys: String, CodingKey {
            case title, uploader, duration, thumbnail, description
            case webpageURL = "webpage_url"
        }
    }

    // MARK: مسیر باینری

    /// پوشهٔ ابزارهای جانبی (مقصد آپدیت‌ر — باندل فقط‌خواندنی است)
    static var toolsDirectory: URL {
        let dir = AppPaths.root.appendingPathComponent("tools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// ترجیح: نسخهٔ به‌روزشده در App Support ← باینری باندل‌شده ← متغیر محیطی (توسعه/تست)
    static func binaryURL(bundle: Bundle = .main,
                          environment: [String: String] = ProcessInfo.processInfo.environment,
                          toolsDirectory: URL? = nil) -> URL? {
        let tools = toolsDirectory ?? Self.toolsDirectory
        if let env = environment["NESHANKYAR_YTDLP"], !env.isEmpty {
            let u = URL(fileURLWithPath: env)
            if FileManager.default.isExecutableFile(atPath: u.path) { return u }
        }
        let updated = tools.appendingPathComponent("yt-dlp")
        if FileManager.default.isExecutableFile(atPath: updated.path) { return updated }
        if let exe = bundle.executableURL {
            let bundled = exe.deletingLastPathComponent().appendingPathComponent("yt-dlp")
            if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        }
        return nil
    }

    /// ffmpeg باندل‌شده (اختیاری) — برای ادغام ویدیو+صدا و کیفیت بالاتر
    static func ffmpegURL(bundle: Bundle = .main) -> URL? {
        guard let exe = bundle.executableURL else { return nil }
        let bundled = exe.deletingLastPathComponent().appendingPathComponent("ffmpeg")
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil
    }

    private nonisolated(unsafe) static var ffmpegWorksResult = -1   // -1 نامشخص، ۰ نه، ۱ بله

    /// ffmpeg نه فقط وجود داشته باشد، بلکه واقعاً اجرا شود (روی سیلیکون اپل بدون Rosetta نمی‌شود)
    static func ffmpegWorks(bundle: Bundle = .main) -> Bool {
        if ffmpegWorksResult == 1 { return true }
        if ffmpegWorksResult == 0 { return false }
        guard let ff = ffmpegURL(bundle: bundle) else {
            ffmpegWorksResult = 0
            return false
        }
        let p = Process()
        p.executableURL = ff
        p.arguments = ["-version"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            ffmpegWorksResult = p.terminationStatus == 0 ? 1 : 0
        } catch {
            ffmpegWorksResult = 0
        }
        return ffmpegWorksResult == 1
    }

    // MARK: باندل اختیاری PO Token (deno + پلاگین bgutil) — برای دانلود یوتیوب

    /// پوشهٔ پلاگین PO Token در منابع باندل (Resources/yt-dlp-plugins/bgutil)
    static var potPluginDir: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let dir = res.appendingPathComponent("yt-dlp-plugins/bgutil")
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("yt_dlp_plugins").path) ? dir : nil
    }

    /// اسکریپت تولید PO Token (Resources/bgutil-server/build/generate_once.js)
    static var potScriptURL: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let script = res.appendingPathComponent("bgutil-server/build/generate_once.js")
        return FileManager.default.fileExists(atPath: script.path) ? script : nil
    }

    /// deno باندل‌شده در کنار باینری اصلی
    static var denoURL: URL? {
        guard let exe = Bundle.main.executableURL else { return nil }
        let deno = exe.deletingLastPathComponent().appendingPathComponent("deno")
        return FileManager.default.isExecutableFile(atPath: deno.path) ? deno : nil
    }

    /// باندل کامل PO Token موجود است؟ (پلاگین + اسکریپت + deno)
    static var potStackReady: Bool {
        potPluginDir != nil && potScriptURL != nil && denoURL != nil
    }

    // MARK: ساخت آرگومان‌ها (خالص)

    static func outputTemplate(destination: URL) -> String {
        destination.appendingPathComponent("%(title)s.%(ext)s").path
    }

    /// آرگومان‌های مشترک باندل PO Token (اختیاری)
    static func potArguments() -> [String] {
        var args: [String] = []
        if let pluginDir = potPluginDir {
            args += ["--plugin-dirs", pluginDir.path]
        }
        if let script = potScriptURL {
            args += ["--extractor-args", "youtubepot-bgutilscript:script_path=\(script.path)"]
        }
        return args
    }

    static func arguments(mode: OutputMode, url: String, destination: URL, hasFFmpeg: Bool,
                          cookiesPath: String? = nil, cookiesBrowser: String? = nil) -> [String] {
        var args = [
            "--newline", "--no-colors", "--no-warnings", "--no-playlist",
            "-o", outputTemplate(destination: destination),
            "--print", "after_move:filepath",
        ]
        // کوکی مرورگر کاربر — لازمهٔ دانلود یوتیوب در وضعیت فعلی ضدهربات یوتیوب
        if let cookiesPath, !cookiesPath.isEmpty {
            args += ["--cookies", cookiesPath]
        } else if let cookiesBrowser, !cookiesBrowser.isEmpty {
            args += ["--cookies-from-browser", cookiesBrowser]
        }
        // باندل PO Token: پلاگین bgutil + اسکریپت deno — رفع «Sign in to confirm you're not a bot»
        args += potArguments()
        if hasFFmpeg, let ff = ffmpegURL() {
            args += ["--ffmpeg-location", ff.path]
        }

        switch mode {
        case .audio:
            // بدون ffmpeg: مستقیم جریان صدای m4a؛ با ffmpeg: استخراج تمیز m4a
            args += hasFFmpeg
                ? ["-f", "ba", "-x", "--audio-format", "m4a"]
                : ["-f", "ba[ext=m4a]/ba"]
        case .video720:
            args += hasFFmpeg
                ? ["-f", "bv*[height<=720][ext=mp4]+ba[ext=m4a]/b[height<=720]",
                   "--merge-output-format", "mp4"]
                : ["-f", "b[height<=720][ext=mp4]/b[ext=mp4]/b"]
        }

        args.append(url)
        return args
    }

    static func metadataArguments(url: String, cookiesPath: String? = nil, cookiesBrowser: String? = nil) -> [String] {
        var args = ["--dump-single-json", "--no-playlist", "--no-warnings", "--skip-download"]
        if let cookiesPath, !cookiesPath.isEmpty {
            args += ["--cookies", cookiesPath]
        } else if let cookiesBrowser, !cookiesBrowser.isEmpty {
            args += ["--cookies-from-browser", cookiesBrowser]
        }
        args += potArguments()
        args.append(url)
        return args
    }

    // MARK: پارس خروجی (خالص)

    /// درصد پیشرفت از خطوط `[download]  42.3% of ...`
    static func progressPercent(from line: String) -> Double? {
        guard line.contains("[download]") else { return nil }
        guard let range = line.range(of: #"\d{1,3}(?:\.\d+)?"# + "%", options: .regularExpression) else { return nil }
        let number = line[range].dropLast()
        return Double(number)
    }

    /// جزئیات زندهٔ خط پیشرفت: حجم کل، سرعت و زمان باقی‌مانده
    /// نمونه: `[download]  42.3% of ~ 10.20MiB at  1.50MiB/s ETA 00:05`
    static func parseProgressDetail(from line: String) -> (total: String?, speed: String?, eta: String?) {
        guard line.contains("[download]") else { return (nil, nil, nil) }
        var total: String?, speed: String?, eta: String?
        if let r = line.range(of: #"of\s+~?\s*[0-9.]+[KMGT]?i?B"#, options: .regularExpression) {
            total = String(line[r]).replacingOccurrences(of: #"of\s+~?\s*"#,
                                                         with: "",
                                                         options: .regularExpression)
        }
        if let r = line.range(of: #"at\s+[0-9.]+[KMGT]?i?B/s"#, options: .regularExpression) {
            speed = String(line[r]).replacingOccurrences(of: #"at\s+"#,
                                                         with: "",
                                                         options: .regularExpression)
        }
        if let r = line.range(of: #"ETA\s+[0-9:]+"#, options: .regularExpression) {
            eta = String(line[r]).replacingOccurrences(of: "ETA ", with: "")
        }
        return (total, speed, eta)
    }

    /// مسیر نهایی فایل از خروجی `--print after_move:filepath` — خطی که براکت ندارد و فایلش هست
    static func outputFilePath(from line: String, fileManager: FileManager = .default) -> String? {
        let trimmed = line.trimmed
        guard !trimmed.isEmpty, !trimmed.hasPrefix("["), !trimmed.hasPrefix("ERROR") else { return nil }
        return FileManager.default.fileExists(atPath: trimmed) ? trimmed : nil
    }

    /// قالب مدت زمان «م:ث» یا «س:د:ث»
    static func durationText(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// قالب نمایشی حجم: 302K / 9.3M / 1.2G
    static func fileSizeText(_ bytes: Int64) -> String {
        let b = Double(max(0, bytes))
        if b < 1024 { return "\(Int(b))B" }
        if b < 1024 * 1024 { return String(format: "%.0fK", b / 1024) }
        if b < 1024 * 1024 * 1024 { return String(format: "%.1fM", b / (1024 * 1024)) }
        return String(format: "%.2fG", b / (1024 * 1024 * 1024))
    }

    /// قالب ساعت‌شمار باقی‌مانده/گذشته: 5 / 1:05 / 1:02:05
    static func clockText(_ totalSeconds: Int) -> String {
        let s = max(0, totalSeconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        if m > 0 { return String(format: "%d:%02d", m, sec) }
        return "\(s)"
    }
    /// اجرای کوتاه با جمع‌آوری کامل خروجی — برای `--dump-single-json` و `--version`
    static func runCollect(_ args: [String]) async throws -> String {
        guard let bin = binaryURL() else { throw ToolError.binaryNotFound }
        let p = Process()
        p.executableURL = bin
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        if let exe = Bundle.main.executableURL {
            env["PATH"] = exe.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        }
        env["LC_ALL"] = "en_US.UTF-8"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - اجرای پروسهٔ yt-dlp با پخش خط‌به‌خط خروجی و لغو

/// فقط از MainActor ساخته و مدیریت می‌شود؛ state داخلی پروسه در دسترس همزمان نیست.
final class YtDlpProcess: @unchecked Sendable {
    private var process: Process?
    private var leftover = ""

    var isRunning: Bool { process?.isRunning ?? false }

    /// اجرا؛ هر خط خروجی (stdout+stderr) به onLine می‌رسد و پایان، onEnd را با کد خروج صدا می‌زند.
    func start(_ args: [String],
               onLine: @escaping @Sendable (String) -> Void,
               onEnd: @escaping @Sendable (Int32) -> Void) throws {
        guard let bin = YtDlp.binaryURL() else { throw YtDlp.ToolError.binaryNotFound }

        let p = Process()
        p.executableURL = bin
        p.arguments = args
        // PATH شامل پوشهٔ باینری اپ: yt-dlp باید deno و ffmpeg باندل‌شده را پیدا کند
        var env = ProcessInfo.processInfo.environment
        if let exe = Bundle.main.executableURL {
            let macDir = exe.deletingLastPathComponent().path
            env["PATH"] = macDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        }
        env["LC_ALL"] = "en_US.UTF-8"   // پیشرفت/خطاها همیشه انگلیسی تا پارس پایدار بماند
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        leftover = ""

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            let chunk = String(data: data, encoding: .utf8) ?? ""
            let lines = (self.leftover + chunk).split(separator: "\n", omittingEmptySubsequences: false)
            // آخرین تکه ممکن است نیمه‌تمام باشد → در بافر می‌ماند
            self.leftover = lines.last.map(String.init) ?? ""
            let complete = lines.dropLast()
            let ready = complete.map { String($0).trimmed }.filter { !$0.isEmpty }
            guard !ready.isEmpty else { return }
            DispatchQueue.main.async {
                ready.forEach(onLine)
            }
        }

        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            // بافر باقی‌مانده (اگر بدون \n تمام شد)
            if let tail = self?.leftover.trimmed, !tail.isEmpty {
                self?.leftover = ""
                DispatchQueue.main.async { onLine(tail) }
            }
            DispatchQueue.main.async { onEnd(proc.terminationStatus) }
        }

        process = p
        try p.run()
    }

    func cancel() {
        process?.terminate()
    }
}
