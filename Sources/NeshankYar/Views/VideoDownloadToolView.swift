import SwiftUI
import AppKit

// MARK: - پنجرهٔ نیتیو «دانلود ویدیو» (بخش ابزارها)

@MainActor
final class VideoDownloadToolWindow: NSObject, NSWindowDelegate {
    static let shared = VideoDownloadToolWindow()

    private var window: NSWindow?
    let model = VideoDownloadToolModel()

    /// باز کردن از آیتم سایدبار — در صورت انتخاب نشانک یوتیوبی، URL پر می‌شود
    func show(bookmark: Bookmark?) {
        if window == nil { makeWindow() }
        model.prepare(bookmark: bookmark)
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() {
        let view = VideoDownloadToolView(model: model)
            .environment(\.layoutDirection, L.direction)
            .preferredColorScheme(AppTheme.appearance)

        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = L.tr("Video Downloader")
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 900, height: 640))
        w.contentMinSize = NSSize(width: 720, height: 520)
        w.isReleasedWhenClosed = false
        w.center()
        w.setFrameAutosaveName("VideoDownloadToolWindow")
        w.delegate = self
        w.appearance = nil
        window = w
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.isBusy {
            model.cancel()
        }
        return true
    }
}

// MARK: - رابط پنجره (صحنهٔ زندهٔ دانلود)

struct VideoDownloadToolView: View {
    @ObservedObject var model: VideoDownloadToolModel
    @State private var settingsExpanded = true
    @State private var showConfetti = false
    @State private var appeared = false

    private var tint: Color { AppTheme.accent ?? Color.accentColor }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    heroCard
                    metadataCard
                    urlRow
                    settingsGroup
                    if !model.recent.isEmpty { recentList }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { appeared = true }
        .onChange(of: model.urlText) { _ in model.scheduleMetadataFetch() }
        .onChange(of: model.phase) { _ in
            if model.phase == .finished {
                showConfetti = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    showConfetti = false
                }
            }
        }
    }

    // MARK: سربرگ

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(tint)
            Text(L.tr("Video Downloader"))
                .font(.title3.weight(.semibold))
            Spacer()
            if model.isBusy {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(elapsedText(now: context.date), systemImage: "clock")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Text("yt-dlp")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
    }

    private func elapsedText(now: Date) -> String {
        guard let s = model.startedAt else { return "–" }
        return YtDlp.clockText(Int(now.timeIntervalSince(s)))
    }

    // MARK: صحنهٔ قهرمان (وضعیت زنده)

    private var heroCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ringIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text(heroTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Text(heroSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                heroAction
            }

            if model.isBusy {
                progressZone
                statChips
            } else if model.phase == .finished {
                successBar
            }
            stageRow
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(heroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(heroBorder, lineWidth: 1)
        )
        .overlay(alignment: .center) {
            if showConfetti { ConfettiBurst() }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.phase)
    }

    private var heroGradient: LinearGradient {
        let base: Color = {
            switch model.phase {
            case .finished: return .green
            case .failed: return .orange
            default: return tint
            }
        }()
        return LinearGradient(
            colors: [base.opacity(model.isBusy || model.phase == .finished ? 0.14 : 0.07),
                     base.opacity(0.02)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var heroBorder: Color {
        switch model.phase {
        case .finished: return .green.opacity(0.35)
        case .failed: return .orange.opacity(0.4)
        default: return tint.opacity(model.isBusy ? 0.4 : 0.15)
        }
    }

    private var heroTitle: String {
        switch model.phase {
        case .ready:
            return model.urlText.trimmed.isEmpty ? L.tr("Video Downloader") : (model.info?.title ?? L.tr("Video Downloader"))
        case .running:
            switch model.stage {
            case .fetching: return L.tr("Fetching video info…")
            case .downloading: return model.info?.title ?? L.tr("Downloading…")
            case .finishing: return L.tr("Almost done…")
            case .idle: return L.tr("Preparing…")
            }
        case .finished:
            return L.tr("Your file is ready")
        case .failed:
            return L.tr("Download")
        }
    }

    private var heroSubtitle: String {
        switch model.phase {
        case .ready:
            return L.tr("Separate window: download a video")
        case .running:
            if model.stage == .fetching { return L.tr("Preparing…") }
            var parts: [String] = []
            if let s = model.speedText { parts.append(s) }
            if let d = model.downloadedText { parts.append(d) }
            if let e = model.etaText { parts.append("⏱ " + e) }
            return parts.isEmpty ? model.statusLine : parts.joined(separator: "  •  ")
        case .finished:
            return (model.outputPath as NSString?)?.lastPathComponent ?? ""
        case .failed(let message):
            return message
        }
    }

    @ViewBuilder
    private var heroAction: some View {
        switch model.phase {
        case .ready:
            Button { model.start() } label: {
                Label(L.tr("Download"), systemImage: "arrow.down.circle.fill")
                    .frame(minWidth: 140, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .font(.callout.weight(.semibold))
            .disabled(model.urlText.trimmed.isEmpty)
        case .running:
            Button { model.cancel() } label: {
                Label(L.tr("Cancel"), systemImage: "stop.fill")
                    .frame(minWidth: 140, minHeight: 34)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .font(.callout.weight(.semibold))
            .tint(.red)
        case .finished:
            // حالت پایان: هیچ دکمه‌ای در سربرگ نیست؛ هر دو کنش
            // («دانلود جدید» اول و اصلی، «نمایش در فایندر» دوم و فرعی)
            // یکدست و کنار هم در successBar می‌آیند.
            EmptyView()
        case .failed:
            Button { model.start() } label: {
                Label(L.tr("Try Again"), systemImage: "arrow.clockwise.circle.fill")
                    .frame(minWidth: 140, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .font(.callout.weight(.semibold))
        }
    }

    // MARK: حلقهٔ پیشرفت + نوار

    private var ringIcon: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: 7)
                .frame(width: 64, height: 64)
            if model.isBusy && model.progress > 0.005 {
                Circle()
                    .trim(from: 0, to: max(0.03, model.progress))
                    .stroke(
                        AngularGradient(colors: [tint, .green, tint],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 64, height: 64)
                    .animation(.easeOut(duration: 0.3), value: model.progress)
            }
            if model.isBusy && model.progress <= 0.005 {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(model.isBusy ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false),
                               value: model.isBusy)
            }
            ringCenter
        }
    }

    @ViewBuilder
    private var ringCenter: some View {
        switch model.phase {
        case .ready:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(tint)
                .offset(y: appeared ? -3 : 3)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                           value: appeared)
        case .running:
            if model.progress > 0.005 {
                Text("\(Int((model.progress * 100).rounded()))")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            } else {
                ProgressView()
                    .controlSize(.regular)
            }
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var progressZone: some View {
        if model.stage == .fetching && model.progress <= 0.005 {
            VStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(tint)
                Text(L.tr("Fetching video info…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [tint, .green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * model.progress))
                        .animation(.easeOut(duration: 0.3), value: model.progress)
                    Capsule()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 56)
                        .offset(x: model.isBusy ? geo.size.width + 20 : -76)
                        .animation(.linear(duration: 1.3).repeatForever(autoreverses: false),
                                   value: model.isBusy)
                }
            }
            .frame(height: 10)
        }
    }

    @ViewBuilder
    private var statChips: some View {
        if model.speedText != nil || model.etaText != nil
            || model.downloadedText != nil || model.startedAt != nil {
            HStack(spacing: 6) {
                if let s = model.speedText {
                    statChip(icon: "gauge.with.dots.needle.50percent",
                             title: L.tr("Speed"), value: s)
                }
                if let e = model.etaText {
                    statChip(icon: "timer", title: L.tr("Remaining"), value: e)
                }
                if let d = model.downloadedText {
                    statChip(icon: "tray.and.arrow.down.fill",
                             title: L.tr("Downloaded"), value: d)
                }
                if model.startedAt != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        statChip(icon: "clock", title: L.tr("Elapsed"),
                                 value: elapsedText(now: context.date))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func statChip(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    @ViewBuilder
    private var successBar: some View {
        if model.phase == .finished {
            VStack(alignment: .leading, spacing: 12) {
                Label(L.tr("Finished"), systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                // هر دو کنشِ پایان، یک‌ردیف، یک‌اندازه، یک‌فونت:
                // «دانلود جدید» اول و اصلی (توپُر)، «نمایش در فایندر» دوم و فرعی (کادری)
                HStack(spacing: 10) {
                    Button {
                        model.resetForNewDownload()
                    } label: {
                        Label(L.tr("New Download"), systemImage: "arrow.down.circle.fill")
                            .frame(minWidth: 140, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    // سبزِ صریح: کنش اصلی باید در یک نگاه از دکمهٔ فرعی
                    // متمایز باشد و با وضعیت «انجام شد» هم‌خانواده بماند —
                    // تکیه به accent سیستم، در حالت گرافیتی خاکستری می‌شود.
                    .tint(.green)
                    Button {
                        if let p = model.outputPath { model.reveal(path: p) }
                    } label: {
                        Label(L.tr("Show in Finder"), systemImage: "magnifyingglass")
                            .frame(minWidth: 140, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .font(.callout.weight(.semibold))
            }
        }
    }

    // MARK: چک‌لیست مرحله‌ها

    private var stageRow: some View {
        HStack(spacing: 4) {
            stageStep(index: 0, title: L.tr("Link"),
                      state: linkStepState)
            stageStep(index: 1, title: L.tr("Details"),
                      state: model.info != nil ? .done
                        : (linkDone && model.phase == .running ? .active : .todo))
            stageStep(index: 2, title: L.tr("Download"),
                      state: downloadStepState)
            stageStep(index: 3, title: L.tr("Done"),
                      state: model.phase == .finished ? .done
                        : (model.stage == .finishing ? .active : .todo))
        }
    }

    private enum StepState { case todo, active, done }

    private var linkDone: Bool {
        guard let u = URL(string: model.urlText.trimmed) else { return false }
        return u.scheme?.hasPrefix("http") == true
    }

    private var linkStepState: StepState {
        if linkDone { return .done }
        if model.phase == .running { return .active }
        return .todo
    }

    private var downloadStepState: StepState {
        if model.phase == .finished { return .done }
        if model.stage == .downloading || model.stage == .finishing { return .active }
        if case .failed = model.phase { return .todo }
        return model.progress > 0 ? .active : .todo
    }

    private func stageStep(index: Int, title: String, state: StepState) -> some View {
        HStack(spacing: 5) {
            switch state {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            case .active:
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 13, height: 13)
            case .todo:
                Image(systemName: "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            Text(title)
                .font(.system(size: 11, weight: state == .active ? .semibold : .regular))
                .foregroundStyle(state == .todo ? .tertiary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(state == .active ? tint.opacity(0.12)
                            : Color.primary.opacity(0.04))
        )
        .animation(.easeInOut(duration: 0.25), value: model.stage)
        .frame(maxWidth: .infinity)
    }

    // MARK: کارت متادیتا

    @ViewBuilder
    private var metadataCard: some View {
        if let info = model.info {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .center) {
                    Group {
                        if let urlString = info.thumbnailURL, let url = URL(string: urlString) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.primary.opacity(0.05)
                            }
                        } else {
                            Color.primary.opacity(0.05)
                        }
                    }
                    .frame(width: 148, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(radius: 4)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let dur = info.durationText {
                        Text(dur)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.75)))
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title ?? "—")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let channel = info.channel { Text(channel).lineLimit(1) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    sourceBadge
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch model.source {
        case .youtube:
            Label("YouTube", systemImage: "play.rectangle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.red)
        case .aparat:
            Label("Aparat", systemImage: "play.rectangle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.blue)
        case .direct:
            Label(L.tr("Best available quality"), systemImage: "arrow.down.doc.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: فیلد لینک

    private var urlRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.tr("Video Link"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("https://www.youtube.com/watch?v=…", text: $model.urlText)
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)
                if !model.urlText.isEmpty {
                    Button {
                        model.urlText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(linkDone ? 0.45 : 0.12), lineWidth: linkDone ? 1.5 : 1)
            )
            .animation(.easeInOut(duration: 0.25), value: linkDone)
        }
    }

    // MARK: تنظیمات (جمع‌شونده)

    private var settingsGroup: some View {
        DisclosureGroup(L.tr("Download Settings"), isExpanded: $settingsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                modePicker
                cookiesSection
                destinationRow
            }
            .padding(.top, 8)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.03)))
    }

    // MARK: انتخاب خروجی

    @ViewBuilder
    private var modePicker: some View {
        if model.showsModePicker {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.tr("Output"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $model.mode) {
                    ForEach(YtDlp.OutputMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.isBusy)
            }
        } else if model.source == .aparat {
            Text(L.tr("Best available quality"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: کوکی یوتیوب

    private var cookiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: model.youtubeAccessible ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(model.youtubeAccessible ? Color.green : Color.orange)
                Text(L.tr("YouTube Access"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if model.hasCookiesFile {
                    Button(L.tr("Remove")) { model.removeCookiesFile() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            if model.hasCookiesFile {
                Label(L.tr("Cookies file is active"), systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !model.cookiesBrowser.isEmpty {
                Label(L.tf("Active from browser: %@", model.cookiesBrowser), systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L.tr("YouTube requires your browser cookies for downloads. Log into YouTube in your browser, then:"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Menu {
                        ForEach(VideoDownloadToolModel.browserOptions, id: \.self) { name in
                            Button(name) { model.cookiesBrowser = name }
                        }
                    } label: {
                        Label(L.tr("Use installed browser"), systemImage: "globe")
                            .font(.caption)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()

                    Button(L.tr("Import cookies.txt File")) { model.importCookiesFile() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }

                Text(L.tr("Export cookies.txt with a browser extension (e.g. “Get cookies.txt LOCALLY”), or pick your browser above. Your cookies stay on this Mac."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(model.youtubeAccessible ? 0.04 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(model.youtubeAccessible ? 0.15 : 0.4))
        )
    }

    // MARK: مقصد

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.tr("Destination Folder"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text((model.destination as NSString).lastPathComponent)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .help(model.destination)
                Spacer()
                Button(L.tr("Change…")) { model.pickDestination() }
                    .buttonStyle(.borderless)
                    .disabled(model.isBusy)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.045)))
        }
    }

    // MARK: دانلودهای اخیر (جلسهٔ جاری)

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.tr("Recent Downloads"))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(model.recent) { item in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(item.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        model.reveal(path: item.path)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(L.tr("Show in Finder"))
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
            }
        }
    }
}

// MARK: - بارش شادی (کانفتی پایان دانلود)

private struct ConfettiBurst: View {
    @State private var start: Date?
    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = start.map { context.date.timeIntervalSince($0) } ?? 0
            let k = min(1, t / 1.1)
            let e = 1 - pow(1 - k, 2)
            ZStack {
                ForEach(0..<36, id: \.self) { i in
                    piece(at: i, e: e, k: k)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { start = Date() }
        .allowsHitTesting(false)
    }

    private func piece(at i: Int, e: Double, k: Double) -> some View {
        let a = Double(i) * 2.39996
        let d = (56 + Double(i % 6) * 20) * e
        let dir: Double = i % 2 == 0 ? 1 : -1
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(colors[i % colors.count])
            .frame(width: 7, height: 4)
            .offset(x: cos(a) * d, y: sin(a) * d - 34 * e)
            .rotationEffect(.degrees(a * 57.3 + 360 * e * dir))
            .opacity(1 - k)
    }
}
