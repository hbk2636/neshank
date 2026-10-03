import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - ماشین حالت ابزار «دانلود ویدیو»

@MainActor
final class VideoDownloadToolModel: ObservableObject {

    enum Phase: Equatable {
        case ready
        case running
        case finished
        case failed(String)
    }

    /// اطلاعات نمایشی ویدیو — از هر بک‌انندی یکدست می‌آید
    struct VideoInfo: Equatable {
        let title: String?
        let channel: String?
        let durationText: String?
        let thumbnailURL: String?
    }

    struct RecentItem: Identifiable, Equatable {
        let id = UUID()
        let path: String
        let name: String
        let date: Date
    }

    // ورودی
    @Published var urlText = ""
    @Published var mode: YtDlp.OutputMode = .video720

    // وضعیت
    @Published var phase: Phase = .ready
    @Published var progress: Double = 0
    @Published var statusLine = ""
    @Published var outputPath: String?
    @Published var recent: [RecentItem] = []
    /// جزئیات زندهٔ دانلود (سرعت، باقی‌مانده، حجم) — نما را زنده نگه می‌دارد
    @Published var speedText: String?
    @Published var etaText: String?
    @Published var totalText: String?
    @Published var downloadedText: String?
    @Published var startedAt: Date?

    /// مرحلهٔ نمایشی برای چک‌لیست زندهٔ نما
    enum DlStage: Equatable { case idle, fetching, downloading, finishing }
    @Published var stage: DlStage = .idle

    // متادیتای ویدیو (با تغییر URL واکشی می‌شود)
    @Published var info: VideoInfo?

    // مقصد — انتخاب کاربر در UserDefaults می‌ماند تا با باز/بسته شدن برنامه برنگردد
    static let destinationKey = "ytdlpDestination"
    @Published var destination: String = VideoDownloadToolModel.savedDestination() {
        didSet {
            UserDefaults.standard.set(destination, forKey: Self.destinationKey)
            try? FileManager.default.createDirectory(
                at: URL(fileURLWithPath: destination), withIntermediateDirectories: true)
        }
    }

    // کوکی یوتیوب — برای دانلود یوتیوب لازم است (فایل cookies.txt یا مرورگر)
    @Published var cookiesBrowser: String {
        didSet { UserDefaults.standard.set(cookiesBrowser, forKey: "ytdlpCookiesBrowser") }
    }
    static var cookiesFilePath: String {
        YtDlp.toolsDirectory.appendingPathComponent("cookies.txt").path
    }
    var hasCookiesFile: Bool { FileManager.default.fileExists(atPath: Self.cookiesFilePath) }
    var cookiesActivePath: String? { hasCookiesFile ? Self.cookiesFilePath : nil }
    var cookiesActiveBrowser: String? { cookiesBrowser.isEmpty ? nil : cookiesBrowser }
    var youtubeAccessible: Bool { hasCookiesFile || !cookiesBrowser.isEmpty || YtDlp.potStackReady }

    private var process: YtDlpProcess?
    private var metadataTask: Task<Void, Never>?
    private var downloadSession: URLSession?

    init() {
        cookiesBrowser = UserDefaults.standard.string(forKey: "ytdlpCookiesBrowser") ?? ""
    }

    static func defaultDestination() -> String {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("نشانکیار", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    /// مقصد ذخیره‌شدهٔ کاربر؛ اگر نباشد یا پوشه‌اش دیگر معتبر نباشد، پیش‌فرض.
    /// (مثلاً پوشه روی فلشی بوده که حالا وصل نیست → دوباره ساخته می‌شود؛
    /// اگر ساخت ممکن نباشد، پیش‌فرض برمی‌گردد تا دانلود به خطا نخورد.)
    static func savedDestination() -> String {
        if let saved = UserDefaults.standard.string(forKey: destinationKey),
           !saved.trimmed.isEmpty {
            try? FileManager.default.createDirectory(
                at: URL(fileURLWithPath: saved), withIntermediateDirectories: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: saved, isDirectory: &isDir),
               isDir.boolValue {
                return saved
            }
        }
        return defaultDestination()
    }

    var isBusy: Bool { phase == .running }
    var source: VideoSource { VideoSource.detect(urlText) }
    /// انتخابگر کیفیت فقط برای مسیر yt-dlp (یوتیوب) معنا دارد؛ آپارات بهترین را می‌دهد
    var showsModePicker: Bool { source == .youtube }

    // MARK: آماده‌سازی از سایدبار

    func prepare(bookmark: Bookmark?) {
        if let b = bookmark, VideoSource.detect(b.url) != .direct {
            urlText = b.url
        }
    }

    // MARK: واکشی متادیتا (با تاخیر کوتاه پس از تایپ)

    func scheduleMetadataFetch() {
        metadataTask?.cancel()
        let url = urlText.trimmed
        guard URL(string: url)?.scheme?.hasPrefix("http") == true else {
            info = nil
            return
        }
        metadataTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.fetchMetadata(url: url)
        }
    }

    private func fetchMetadata(url: String) async {
        switch VideoSource.detect(url) {
        case .aparat:
            guard let id = AparatBackend.videoID(from: url),
                  let video = try? await AparatBackend.fetchVideo(id: id) else { return }
            guard self.urlText.trimmed == url else { return }
            info = VideoInfo(title: video.title,
                             channel: video.username,
                             durationText: YtDlp.durationText(video.duration.map(Double.init)),
                             thumbnailURL: video.bigPoster)
        case .youtube:
            guard let json = try? await YtDlp.runCollect(YtDlp.metadataArguments(
                url: url,
                cookiesPath: cookiesActivePath,
                cookiesBrowser: cookiesActiveBrowser)),
                let data = json.data(using: .utf8),
                let meta = try? JSONDecoder().decode(YtDlp.VideoMetadata.self, from: data) else { return }
            guard self.urlText.trimmed == url else { return }
            info = VideoInfo(title: meta.title,
                             channel: meta.uploader,
                             durationText: YtDlp.durationText(meta.duration),
                             thumbnailURL: meta.thumbnail)
        case .direct:
            info = VideoInfo(title: (url as NSString).lastPathComponent,
                             channel: nil, durationText: nil, thumbnailURL: nil)
        }
    }

    // MARK: دانلود

    func start() {
        guard !isBusy else { return }
        let url = urlText.trimmed
        guard URL(string: url)?.scheme?.hasPrefix("http") == true else {
            phase = .failed(L.tr("This address is not a valid video link."))
            return
        }
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: destination),
                                                 withIntermediateDirectories: true)
        progress = 0
        outputPath = nil
        speedText = nil
        etaText = nil
        totalText = nil
        downloadedText = nil
        startedAt = Date()
        stage = .fetching
        phase = .running

        switch source {
        case .aparat:
            startAparat(url: url)
        case .youtube:
            startYtDlp(url: url)
        case .direct:
            startYtDlp(url: url)
        }
    }

    private func startYtDlp(url: String) {
        statusLine = L.tr("Preparing…")
        guard YtDlp.binaryURL() != nil else {
            phase = .failed(L.tr("The yt-dlp tool was not found inside the app."))
            return
        }
        let dest = URL(fileURLWithPath: destination)
        let hasFFmpeg = YtDlp.ffmpegWorks()
        let args = YtDlp.arguments(mode: mode, url: url, destination: dest, hasFFmpeg: hasFFmpeg,
                                   cookiesPath: cookiesActivePath,
                                   cookiesBrowser: cookiesActiveBrowser)

        let proc = YtDlpProcess()
        process = proc
        do {
            try proc.start(args, onLine: { [weak self] line in
                Task { @MainActor [weak self] in self?.handleLine(line) }
            }, onEnd: { [weak self] code in
                Task { @MainActor [weak self] in self?.handleEnd(code) }
            })
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func handleLine(_ line: String) {
        guard phase == .running else { return }
        if let percent = YtDlp.progressPercent(from: line) {
            progress = min(1, percent / 100)
            stage = .downloading
            if statusLine != L.tr("Downloading…") { statusLine = L.tr("Downloading…") }
            let detail = YtDlp.parseProgressDetail(from: line)
            if let t = detail.total { totalText = t }
            if let s = detail.speed { speedText = s }
            if let e = detail.eta { etaText = e }
            if let t = detail.total {
                downloadedText = String(format: "%.0f%% · %@",
                                        min(100, percent), t)
            }
        } else if line.hasPrefix("[Merger]") || line.hasPrefix("[ExtractAudio]")
                    || line.hasPrefix("[VideoRemuxer]") {
            stage = .finishing
            statusLine = L.tr("Almost done…")
        }
        if let path = YtDlp.outputFilePath(from: line) {
            outputPath = path
        }
        if line.hasPrefix("ERROR") {
            statusLine = line
        }
    }

    private func handleEnd(_ code: Int32) {
        guard phase == .running else { return }   // لغو شده
        if code == 0, let path = outputPath {
            finish(path: path)
        } else if statusLine.hasPrefix("ERROR") {
            phase = .failed(statusLine)
        } else {
            phase = .failed(L.tr("Download failed. Check the link and your connection."))
        }
    }

    // MARK: دانلود آپارات — URLSession با پیشرفت

    private func startAparat(url: String) {
        statusLine = L.tr("Resolving…")
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let id = AparatBackend.videoID(from: url) else {
                    self.phase = .failed(L.tr("This address is not a valid video link."))
                    return
                }
                let video = try await AparatBackend.fetchVideo(id: id)
                guard let link = video.fileLink, let fileURL = URL(string: link) else {
                    self.phase = .failed(L.tr("This address is not a valid video link."))
                    return
                }
                self.info = VideoInfo(title: video.title,
                                      channel: video.username,
                                      durationText: YtDlp.durationText(video.duration.map(Double.init)),
                                      thumbnailURL: video.bigPoster)
                self.statusLine = L.tr("Downloading…")

                let fileName = Self.fileName(for: video.title ?? "aparat", ext: "mp4")
                let dest = URL(fileURLWithPath: destination).appendingPathComponent(fileName)

                // انتقال فایل حالا داخل خود delegate و «همزمان» انجام می‌شود؛
                // اینجا فقط وضعیت نهایی را ثبت می‌کنیم.
                let delegate = ProgressDownloadDelegate(
                    destination: dest,
                    onProgress: { [weak self] value in
                        Task { @MainActor [weak self] in
                            guard let self, self.phase == .running else { return }
                            self.progress = value
                            self.stage = .downloading
                            self.statusLine = L.tr("Downloading…")
                        }
                    },
                    onBytes: { [weak self] written, expected in
                        Task { @MainActor [weak self] in
                            guard let self, self.phase == .running else { return }
                            if expected > 0 {
                                self.totalText = YtDlp.fileSizeText(expected)
                                self.downloadedText = "\(YtDlp.fileSizeText(written)) · \(YtDlp.fileSizeText(expected))"
                            } else {
                                self.downloadedText = YtDlp.fileSizeText(written)
                            }
                            if let start = self.startedAt {
                                let elapsed = max(0.5, Date().timeIntervalSince(start))
                                let bps = Double(written) / elapsed
                                self.speedText = YtDlp.fileSizeText(Int64(bps)) + "/s"
                                if expected > written, bps > 0 {
                                    let remain = Int((Double(expected - written) / bps).rounded())
                                    self.etaText = YtDlp.clockText(remain)
                                }
                            }
                        }
                    },
                    onFinish: { [weak self] result in
                        Task { @MainActor [weak self] in
                            guard let self, self.phase == .running else { return }
                            switch result {
                            case .success(let file):
                                self.finish(path: file.path)
                            case .failure(let error):
                                self.phase = .failed(error.localizedDescription)
                            }
                        }
                    })
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                downloadSession = session
                session.downloadTask(with: fileURL).resume()
            } catch {
                guard self.phase == .running else { return }
                self.phase = .failed(L.tr("Download failed. Check the link and your connection."))
            }
        }
    }

    static func fileName(for title: String, ext: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let clean = title.components(separatedBy: bad).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean.isEmpty ? "video" : clean) + "." + ext
    }

    // MARK: پایان

    private func finish(path: String) {
        phase = .finished
        outputPath = path
        recent.insert(RecentItem(path: path,
                                 name: (path as NSString).lastPathComponent,
                                 date: Date()), at: 0)
    }

    /// بازنشانی کامل برای «دانلود جدید» — لینک قبلی هم پاک می‌شود
    /// تا کاربر بتواند بلافاصله لینک تازه بگذارد و دوباره کار کند.
    func resetForNewDownload() {
        outputPath = nil
        phase = .ready
        stage = .idle
        progress = 0
        info = nil
        statusLine = ""
        speedText = nil
        etaText = nil
        totalText = nil
        downloadedText = nil
        startedAt = nil
        urlText = ""
    }

    // MARK: لغو

    func cancel() {
        guard isBusy else { return }
        process?.cancel()
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
        phase = .ready
        stage = .idle
        statusLine = L.tr("Download cancelled.")
    }

    // MARK: پوشه

    func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: destination)
        panel.message = L.tr("Choose the download destination folder")
        if panel.runModal() == .OK, let url = panel.url {
            destination = url.path
        }
    }

    func reveal(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
    }

    // MARK: کوکی‌ها

    static let browserOptions = ["safari", "firefox", "chrome", "edge", "brave", "vivaldi", "opera", "whale"]

    func importCookiesFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data, .plainText]
        panel.message = L.tr("Choose the exported cookies.txt file")
        if panel.runModal() == .OK, let url = panel.url {
            let dest = URL(fileURLWithPath: Self.cookiesFilePath)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                objectWillChange.send()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func removeCookiesFile() {
        try? FileManager.default.removeItem(atPath: Self.cookiesFilePath)
        objectWillChange.send()
    }
}
