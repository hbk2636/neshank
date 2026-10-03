<a id="english"></a>
<div align="center">
  <img src="./Resources/logo.png" alt="Neshank logo" width="110">
  <h1>📌 Neshank</h1>
  <p>
    <b>Native, offline-first bookmark manager for macOS</b> — folders &amp; full-text search,
    AI chat about your saved links, link&nbsp;→&nbsp;visual&nbsp;mind&nbsp;map,
    a built-in free video downloader, and a menu-bar quick box.
  </p>
  <p>原生离线 macOS 书签管理器 — AI 对话、思维导图、内置免费视频下载器。</p>
  <p dir="rtl">مدیر نشانک بومی مک — گفتگوی AI، نقشهٔ ذهنی، دانلودر رایگان، کاملاً آفلاین.</p>
  <p>
    <img src="https://img.shields.io/badge/platform-macOS%2013%2B%20%C2%B7%20Apple%20Silicon-1f6feb" alt="macOS 13+ · Apple Silicon">
    <img src="https://img.shields.io/badge/Swift%20%C2%B7%20SwiftUI-f05138" alt="Swift · SwiftUI">
    <img src="https://img.shields.io/badge/version-1.0-blue" alt="version 1.0">
    <img src="https://img.shields.io/badge/tests-57%20passed-brightgreen" alt="57 tests passed">
    <img src="https://img.shields.io/github/downloads/hbk2636/neshank/total?label=downloads&color=blue" alt="total downloads">
    <img src="https://img.shields.io/github/stars/hbk2636/neshank?label=stars&color=yellow" alt="GitHub stars">
    <a href="https://github.com/hbk2636/neshank/actions/workflows/ci.yml"><img src="https://github.com/hbk2636/neshank/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
    <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license">
  </p>
  <p>English · <a href="#chinese">简体中文</a> · <a href="#persian">فارسی</a> · <a href="#russian">Русский</a> · <a href="../../releases/latest">⬇️ Download v1</a></p>
</div>

Neshank (**نشانک**, "bookmark") is an open-source **bookmark manager for macOS** built with **SwiftUI + SQLite** — no Electron, no cloud, no account, no Xcode required to build. It replaces a folder of scattered links with a fast, offline-first library where every saved page is **archived, searchable and ready to talk to**.

<p align="center">
  <img src="docs/assets/demo.gif" alt="Neshank demo — library, mind map, video downloader and AI chat" width="760">
</p>

<p align="center">⭐ <b>If Neshank saves you time, star the repo</b> — it takes a second and helps others find this free tool.</p>

<table>
  <tr>
    <td><img src="./docs/assets/screenshot-main.png" width="100%" alt="Neshank main window — bookmark library with folders, tags and instant search"></td>
    <td><img src="./docs/assets/screenshot-mindmap.png" width="100%" alt="Link to visual mind map generator with 6 layouts and color themes"></td>
  </tr>
  <tr>
    <td><img src="./docs/assets/screenshot-downloader.png" width="100%" alt="Built-in free video downloader for YouTube, Aparat and 1700+ sites"></td>
    <td><img src="./docs/assets/screenshot-assistant.png" width="100%" alt="AI chat assistant panel for bookmarked links — quick questions and free chat"></td>
  </tr>
</table>

### ✨ Highlights

|  | Feature | What you get |
|---|---------|--------------|
| 🗂️ | **Bookmark manager** | Hierarchical folders, multi-tags, instant search over title / URL / notes / tags **and full page text** (SQLite FTS5), full-page screenshots, link health checker, trash with ⌘Z, Safari / Chrome / Firefox import-export |
| 📦 | **Menu-bar quick box** | A tiny box in the macOS menu bar — right next to battery & input indicator — paste a link and save it without opening the app window |
| ⌨️ | **Global hotkey** | One shortcut (default **⌘⇧Space**, remappable to ⌘⇧A / ⌘⇧H or off) opens the floating quick-add panel **from any app**, with no Accessibility permission needed (Carbon HotKey) |
| 🤖 | **AI chat about your links** | Connect any **OpenAI-compatible `/v1` provider** and pick the model in Settings. Ask *“does this fit my budget?”, pros/cons, 5-point summaries* — per bookmark, or across the whole library with numbered citations `[1] [2]` |
| 🧠 | **Link → visual mind map** | Turn a link (or a selection of bookmarks) into a visual mind map — **6 layouts/templates** in multiple color themes, engineered to stay useful even with **small / free models**. Live views: map · tree · markdown · JSON |
| ⬇️ | **Free video downloader** | Built-in downloader for **YouTube, Aparat and 1,700+ sites** (bundled `yt-dlp` — zero setup, no account, no server). Up to **720p in v1**, better quality coming |

### 🧰 Everything else

6 complete UI layouts (Classic, Aurora, Focus, Dashboard, Atlas, Orbit) · 10 accent colors + 6 themes · light/dark · full-page article archive with deep search · **Today** page (⌘⇧T) · command palette (**⌘K**) · decision log (“bought / skipped / maybe”) · saved filters · duplicate finder · folder colors & icons · multi-select bulk actions · daily automatic backups · Persian (RTL), English, Russian, Chinese localization · works fully offline.

## 📖 About Neshank (نشانک) — the full picture

**The problem every heavy internet user knows.** You save a great article, a product page, a tutorial or a video, and it disappears into a browser bookmark bar that nobody ever opens again. Months later you need that link and it is gone — buried under a thousand siblings, hidden behind an expired domain, or scattered across three browsers, two note apps and a chat history. “Read later” lists become shame piles. Link rot eats the useful parts of the web. Browser bookmark managers were never designed to be a **library**: they cannot search inside the pages you saved, cannot tell you which links are still alive, cannot help you decide anything, and cannot turn a pile of URLs into a picture you can actually think with.

**Neshank (نشانک — Persian for “bookmark”) is a native macOS app that turns saved links into an offline-first knowledge library.** One SQLite database on your Mac, a fast SwiftUI interface, and six jobs done properly:

**1. Capture in one gesture.** A tiny quick-add box lives in the macOS menu bar right next to the battery indicator — paste a link and it is saved without opening the main window. A global hotkey (default **⌘⇧Space**, remappable to ⌘⇧A / ⌘⇧H or disabled) summons a floating quick-add panel from *any* application, with no Accessibility permission required (Carbon HotKey). Press **⌘V** anywhere that is not a text field and the panel opens with your clipboard URL already filled. Drag a link out of any browser onto the window and the panel appears. Titles, descriptions, favicons and og-images are fetched automatically while you type nothing.

**2. Organize without effort.** Hierarchical folders with inline expand/collapse, right-click subfolders and safe deletion that never orphans children; ten-color palette plus sixteen icons per folder; multi-tags; saved filters that remember search + scope + sort under a name; a duplicate finder that normalizes URLs (http/https, www, tracking parameters) and keeps the newest copy; grouping by domain, Persian calendar month or folder; multi-select bulk actions (move, tag, mark read, archive, delete); a 30-day trash with **⌘Z** undo and an explicit “empty trash”; Netscape-format import and export for Safari, Chrome and Firefox.

**3. Read forever.** When you save a page, its full text is archived locally (toggle-able), so even if the site dies, the words stay — and they are indexed: full-text search (SQLite **FTS5** with LIKE fallback) reaches *inside* page contents, not just titles and URLs. Neshank takes a real screenshot of each page with WKWebView so your library looks like a magazine, not a list (empty/error captures are detected automatically). A link checker batch-tests health (HEAD with GET fallback) and separates “dead” from “unknown”. Daily automatic backups, schema-versioned migrations that never wipe your data, and a manual backup button round out the safety story.

**4. Talk to your links — the AI chatbot.** Connect **any OpenAI-compatible `/v1` provider** — OpenAI, OpenRouter, local Ollama, or a self-hosted server — enter base URL, API key and model in *Settings → Assistant*, press *Test Connection*, and you are done: the app ships **no default cloud**, your key never leaves your Mac. On any bookmark, the ✦ button (or **⌘⇧D**) opens a persistent chat about that page: “does this fit my budget?”, “5-point summary”, “pros and cons”, “risks and downsides”, “compare against my profile”, “questions to ask before buying”, or free-form conversation. Context = the archived page text + title/URL/notes/tags + your written profile; if the text was not archived, the assistant reads the page itself on first ask. Answers are instructed to stay honest — prices and stock only when present on the page (“according to this page”), nothing guessed. A **library-wide chat** answers questions across *all* bookmarks with numbered citations **[1] [2]** and clickable source chips. Every answer can get a decision log entry — bought / skipped / maybe, with a note and date — visible later as a badge on the bookmark. Per-link chats persist; the Chats page (**⌘⇧C**) searches, renames, pins, restarts or deletes them. Crucially, prompts are tuned so that even **small and free models** return useful output — no GPT-4 dependency.

**5. See the big picture — link → mind map generator.** Give it a link (or a selection of bookmarks) and Neshank builds a **visual mind map** from the page’s archived content: **6 layouts/templates** — including a balanced two-sided Buzan/XMind-style map with the root centered and branches alternating left/right — in multiple color themes, with four always-alive views (**map · tree · markdown · JSON**) that switch instantly without reload. The renderer is a single self-contained offline `canvas.html` bundled in the app: no remote resources, no Electron, works on a plane. The generation prompts are engineered to produce a sane structure even from **weak, small or free AI models** — this is the feature people screenshot and share.

**6. Download video — free, built-in.** A complete **video downloader for macOS** ships inside the app: **YouTube, Aparat, SoundCloud, TikTok, Dailymotion and 1,700+ other sites** through a bundled, auto-updating `yt-dlp` engine plus `ffmpeg` — zero setup, no account, no server, no paid API. Paste a URL (or click a YouTube bookmark, which is auto-detected as “ready to download”), watch live progress, and save to the folder you chose. Video metadata — title, channel, duration, thumbnail — fills a new bookmark without opening the browser, and subtitles can be archived into the library so your deep search and AI assistant can search *inside videos* too. Version 1 supports up to **720p**; higher qualities are on the roadmap. It is the best free YouTube downloader for Mac that also works as a generic video downloader — while you should always respect each site’s terms of service.

**Multilingual — English, 简体中文, فارسی, Русский.** Built English-first: complete English UI and documentation, a full Simplified Chinese interface, Persian with a first-class right-to-left layout (Persian numerals, calendar month grouping) — and Russian. Every label lives in one localization dictionary with CI-checked health. Six full UI design shells let the app become whatever you want: a classic three-pane Mac browser-style library, a glassy Aurora tab-bar with big visual cards, a typographic Focus column, a widget Dashboard with tag clouds, an Atlas catalogue with serif typography, or an Orbit tile launcher — with 10 accent colors, 6 gradient themes and light/dark on top.

**Native, small, private.** Built with **SwiftUI + SQLite (WAL, FTS5)** — no Electron, no bundled browser runtime, no telemetry, no account, no cloud sync, no subscription. Everything lives in `~/Library/Application Support/NeshankYar/`. The app works fully offline; the network is only used for fetching page metadata, screenshots, link checks, downloads and *your* AI provider. It targets Apple Silicon on macOS 13+, is ad-hoc signed, builds with only the Command Line Tools (**no Xcode needed**), and is released under the **MIT** license with a **57-check test suite** running in GitHub Actions on every push.

**Who is it for?** Researchers and students archiving papers before they vanish; developers collecting documentation; shoppers who want an AI second opinion before buying; creators downloading reference videos at 720p; educators building visual mind maps from lecture links; and the Persian-speaking community that has waited for a serious, beautiful, RTL-native bookmarking tool that is not SaaS and not spyware.

**In one sentence:** Neshank is the free, open-source, offline-first **bookmark manager for macOS** with an **AI assistant chatbot for your links**, a **link-to-mind-map generator**, and a built-in **YouTube / video downloader** — private by design, gorgeous by default.

### ❓ Quick FAQ

- **Is it free?** Yes — MIT-licensed, no paid tier, no account, forever.
- **Does the YouTube downloader work without any setup?** Yes — `yt-dlp` and `ffmpeg` are bundled inside the app; install the DMG and download (up to 720p in v1).
- **Do I need a ChatGPT subscription?** No — bring any OpenAI-compatible key (including local Ollama) or use free/small models; the key stays on this Mac only.
- **Does it work offline?** Everything except fetching page metadata, screenshots, link checks, downloads and AI calls works with zero network.
- **Does it run on Intel Macs?** No — Neshank targets **Apple Silicon (M1 or newer) on macOS 13+**; Intel is not supported in v1.
- **How is this different from cloud bookmark services?** No account, no subscription, no telemetry — nothing leaves your Mac except what you explicitly send. It searches *inside* the pages you saved, talks to them with your own AI key, turns them into mind maps, and downloads videos — one native app.

## ⬇️ Quick start

**Download** **`Neshank-1.dmg`** from the **[Releases page](../../releases/latest)** → open → drag *نشانک* into Applications.

> Gatekeeper note: the app is ad-hoc signed — **right-click → Open** on first launch (or `xattr -cr /Applications/نشانک.app`).

**Build from source** (no Xcode needed, only Command Line Tools):

```bash
git clone https://github.com/hbk2636/neshank.git
cd neshank
./Scripts/build_app.sh        # → build/نشانک.app + نشانک-$VERSION.dmg
open "build/نشانک.app"        # run locally
zsh Scripts/run_tests.sh      # test suite (exit code 1 = failure, CI-friendly)
```

Requirements: **macOS 13+ (Ventura), Apple Silicon**. A full release build downloads the bundled tools once (pinned `yt-dlp`, arm64 `ffmpeg-static`, `deno` + PO-token provider) — end users need nothing.

## 🤖 AI setup (2 minutes)

Settings → **Assistant** → enter any OpenAI-compatible endpoint (OpenAI, OpenRouter, local **Ollama**, …): base URL (…`/v1`), API key, model name → **Test Connection**. Your key never leaves your Mac; only the bookmark you ask about (or cited excerpts for library chats) is sent to *your* provider. Works with free / small models — the mind-map and chat prompts are tuned for them.

## ⌨️ Shortcuts

| Key | Action |
|-----|--------|
| ⌘N | New bookmark |
| ⌘⇧Space | Global quick-add (any app) |
| ⌘K | Command palette (jump, search, ask) |
| ⌘⇧D | AI assistant for the selected bookmark |
| ⌘⇧C / ⌘⇧T | Chats / Today page |
| ⌘V | Paste URL + quick add (when no text field is focused) |
| ⌘Z / ⌘⌫ | Undo delete / move to trash |

The complete shortcut list (14 rows) also appears in each language section below.

## 🏗 Architecture

```
Sources/NeshankYar/
  App/            entry point, window, menu bar, global key monitor, quick box
  Store/          thin SQLite layer (WAL, prepared statements) + main library logic
  Models/         bookmarks/folders/tags, settings, localization (fa/en/ru/zh), AI chat models
  Services/       PageMeta, HTMLText, Screenshotter, HotKey, LinkChecker,
                  ImportExport, AIClient (/v1), YtDlp, VideoBackends, MindMap export
  Views/          root, sidebar, list, details, editor, settings, quick-add panel,
                  mind-map tool, video tool, chats, command palette,
                  Designs/ — Aurora · Focus · Dashboard · Atlas · Orbit shells
  Resources/      MindMap/canvas.html (offline, self-contained), Extractor/ (Readability, Turndown)
Scripts/          build_app.sh (app + ICNS + DMG), run_tests.sh
docs/             design specs & phase reports (mind-map, downloader)
```

## 🧪 Tests

```bash
zsh Scripts/run_tests.sh
```

**57 checks, 0 failures** — URL normalization, localization dictionary health, schema migration, backups (snapshot / failure paths / daily pruning), mind-map layout invariants (balanced map, outline alignment, wire counts) and UI-design integrity. Exit code 1 = failure, so it slots straight into CI.

## 🔗 Related projects & credits

Neshank stands on the shoulders of these open-source projects — thank you:

- [**mind-elixir**](https://github.com/SSShooter/mind-elixir-core) (MIT) — early RTL-capable mind-map foundation the map tool grew from
- [**Mozilla Readability**](https://github.com/mozilla/readability) (Apache-2.0) — article extraction for the full-page archive (bundled with its license)
- [**Turndown**](https://github.com/mixmark-io/turndown) (MIT) — HTML → Markdown conversion (bundled)
- [**yt-dlp**](https://github.com/yt-dlp/yt-dlp) — the download engine bundled inside the app
- [**ffmpeg-static**](https://github.com/eugeneware/ffmpeg-static) · [**deno**](https://github.com/denoland/deno) · [**bgutil-ytdlp-pot-provider**](https://github.com/Brainicism/bgutil-ytdlp-pot-provider) — bundled media & PO-token tooling

## 🔒 Privacy

Local **SQLite** library; archived page text, screenshots and favicon caches stay in `~/Library/Application Support/NeshankYar/`. No telemetry, no account, no sync. Your AI key is stored only in this Mac's preferences — the app works completely offline except fetching page metadata, screenshots, link checks and downloads.

## 📄 License

[MIT](./LICENSE) © hosein shahraki. Bundled third-party tools and libraries keep their own licenses (see Credits).

<br>

## #️⃣ Tags & keywords

`#macos` `#mac` `#apple` `#bookmarks` `#bookmark-manager` `#read-later` `#productivity` `#mindmap` `#mind-map` `#brainstorming` `#video-downloader` `#youtube-downloader` `#youtube` `#downloader` `#ai` `#ai-assistant` `#chatbot` `#chatgpt` `#openai` `#ollama` `#llm` `#swiftui` `#swift` `#offline-first` `#privacy` `#rtl` `#farsi` `#open-source` `#sqlite` `#full-text-search` `#knowledge-management` `#chinese` `#russian` `#i18n`

<a id="chinese"></a>
## 简体中文

**Neshank（书签）** 是一款专为 macOS 打造的 **原生、离线优先的书签管理器** — 免费开源（MIT），基于 SwiftUI + SQLite 构建，无需安装 Xcode。

| 功能 | 说明 |
|---|---|
| 📦 菜单栏快速添加 | 菜单栏小工具一键保存链接；全局快捷键 **⌘⇧Space** 在任何应用中唤起快速添加面板（无需辅助功能权限） |
| 🗂️ 整理与检索 | 多级文件夹、多标签、**全文搜索**（含已存档网页正文，SQLite FTS5）、页面截图、死链检查、回收站 ⌘Z、Safari/Chrome/Firefox 导入导出 |
| 🤖 AI 对话 | 连接任意 OpenAI 兼容 `/v1` 服务（OpenAI、OpenRouter、本地 **Ollama**）——针对单个链接或整个书签库提问，回答带编号引用 [1] [2]；针对**小模型 / 免费模型**专门优化 |
| 🧠 链接 → 思维导图 | **6 种布局模板**、多套配色，完全离线渲染；地图 / 树 / Markdown / JSON 四个实时视图 |
| ⬇️ 内置视频下载器 | YouTube、Aparat、SoundCloud、TikTok、Dailymotion 等 **1700+ 网站**（内置 yt-dlp），零配置、无需账号；v1 最高 720p |
| 🔒 隐私 | 完全离线优先：无账号、无云同步、无遥测，数据只保存在你的 Mac 上 |

**快捷键：** ⌘N 新建 · ⌘⇧Space 全局快速添加 · ⌘K 命令面板 · ⌘⇧D AI 助手 · ⌘⇧T 今日页 · ⌘⇧C 对话页 · ⌘F 搜索

**安装：** 从 [Releases](../../releases/latest) 下载 `Neshank-1.dmg` → 打开 → 拖入「应用程序」。首次启动请 **右键 → 打开**（ad-hoc 签名）。系统要求：**macOS 13+（Apple Silicon）**。

[English](#english) · [فارسی](#persian) · [Русский](#russian)

---

<a id="persian"></a>
## نشانک (NeshankYar) 📌 — نسخهٔ فارسی

<div dir="rtl">

مدیر نشانک **بومی مک** با رابط فارسی راست‌به‌چپ — ساخته‌شده با **SwiftUI + SQLite**، بدون هیچ وابستگی خارجی و بدون نیاز به Xcode (فقط Command Line Tools).

- **نام برنامه:** نشانک
- **نسخه:** ۱ (1.0) — نخستین انتشار عمومی
- **سازنده:** hosein shahraki
- **شناسه:** `com.gozaresh.neshankyar`

![آیکون](./Resources/logo.png)

**دریافت:** [آخرین نسخه از صفحهٔ Releases](../../releases/latest) — بعد از نصب، برای دور زدن Gatekeeper روی برنامه **راست‌کلیک → باز کن (Open)**.

</div>

### ساخت و نصب

```bash
# ساخت کامل: .app + آیکون + امضا + DMG
./Scripts/build_app.sh

# خروجی‌ها
#   build/نشانک.app          برنامه
#   ./نشانک-$VERSION.dmg     بستهٔ نصب (در پوشهٔ پروژه + دسکتاپ)

open "build/نشانک.app"       # اجرای محلی
./Scripts/build_app.sh debug # نسخهٔ debug (سریع‌تر)
zsh Scripts/run_tests.sh     # مجموعهٔ تست (۵۷ موفق)
```

### امکانات

<div dir="rtl">

#### هسته

| بخش | جزئیات |
|---|---|
| افزودن نشانک | ⌘N — دکمهٔ «نشانک جدید» **همیشه در نوار بالای فهرست** دیده می‌شود؛ آدرس را بچسبان، عنوان/توضیح/تصویر/فاوآیکون خودکار از صفحه خوانده می‌شود |
| سازمان‌دهی | پوشهٔ سلسله‌مراتبی (زیرپوشه با کلیک‌راست، باز/بسته‌شدن درون‌خطی با شورون، حذف امن بدون از دست رفتن زیرپوشه‌ها) + برچسب‌های چندتایی |
| جستجو | فوری و debounceشده روی عنوان، آدرس، دامنه، یادداشت، برچسب **و متن کامل صفحات** (FTS5 با fallback به LIKE) |
| فیلترها | همه، ستاره‌دارها، نخوانده‌ها، لینک‌های مرده، بایگانی، زباله‌دان، هر پوشه، هر برچسب |
| نما | سه حالت به انتخاب کاربر (بین اجراها حفظ می‌شود): **فهرست**، **کارت‌های ریسپانسیو**، **سه‌ستونی/باکس** |
| چیدمان | سه ستون ریسپانسیو با جداکنندهٔ قابل کشیدن (عرض ستون‌ها حفظ می‌شود) |
| سلامت لینک | بررسی دسته‌ای (HEAD با fallback به GET)، تمایز «مرده» از «نامشخص» |
| ورودی/خروجی | فرمت Netscape مرورگرها (سافاری/کروم/فایرفاکس) |
| داده | SQLite محلی (WAL) + کش فاوآیکون/تصاویر/عکس‌ها در `~/Library/Application Support/NeshankYar/` |

#### بستهٔ بهره‌وری

| بخش | جزئیات |
|---|---|
| باکس منوی سیستم | **مینی‌باکس افزودن سریع در نوار منوی مک** (کنار باتری و زبان ورودی) — لینک را بچسبان و ذخیره کن، بدون باز کردن پنجرهٔ اصلی |
| افزودن سریعٔ سراسری | **⌘⇧Space** (قابل تغییر: ⌘⇧A / ⌘⇧H / غیرفعال) در هر برنامه‌ای — پنل شناور باز می‌شود، **بدون نیاز به مجوز سیستم** (Carbon HotKey) |
| چسباندن سریع | **⌘V** وقتی فیلد متنی فوکوس نیست → اگر کلیپ‌بورد آدرس باشد، پنل افزودن با آدرس پر می‌شود |
| رهاکردن لینک | لینک را از مرورگر روی پنجرهٔ برنامه **Drag & Drop** کنید → پنل افزودن باز می‌شود |
| حذف امن | حذف = رفتن به **زباله‌دان** (۳۰ روز نگه داشته می‌شود)؛ **⌘Z** آخرین حذف را برمی‌گرداند؛ «خالی کردن زباله‌دان» و «حذف قطعی» هم هست |
| انتخاب چندتایی | **⌘/⇧ کلیک** در هر سه نما + **نوار اقدامات گروهی**: انتقال به پوشه، افزودن برچسب، خوانده، بایگانی، حذف |

#### بستهٔ نقشهٔ ذهنی

| بخش | جزئیات |
|---|---|
| تبدیل لینک به نقشه | لینک (یا چند نشانک انتخاب‌شده) را بده → **نقشهٔ ذهنی بصری** بساز؛ متن صفحه از همان نشانک/آرشیو خوانده می‌شود |
| چیدمان و تمپلیت | **۶ چیدمان/تمپلیت** با چندین رنگ‌بندی — از جمله چیدمان متوازن دوطرفه (ریشه وسط، شاخه‌ها چپ/راست) |
| بهینه برای مدل‌های ضعیف | پرامپت و خروجی طوری تنظیم شده که حتی با **مدل‌های رایگان و کوچک** نتیجهٔ معقول بگیری |
| چهار نمای زنده | نقشه / درخت / مارک‌داون / JSON — همه در یک پنجره، بدون ریلود و بدون از دست رفتن رندر |
| کاملاً آفلاین | بوم رندر یک فایل خودکفا (`canvas.html`) داخل برنامه است — هیچ منبع ریموت لود نمی‌شود |

#### بستهٔ دانلودر ویدیو

| بخش | جزئیات |
|---|---|
| دانلودر داخلی | **YouTube، Aparat و ۱۷۰۰+ سایت** با `yt-dlp` باندل‌شده — بدون نصب ابزار، بدون حساب، بدون سرور |
| کیفیت | در نسخهٔ ۱ تا **۷۲۰p**؛ کیفیت‌های بیشتر در آینده |
| بدون تنظیم | همه‌چیز داخل `.app` است؛ کاربر DMG را نصب می‌کند و **همه‌چیز بدون هیچ تنظیمی** کار می‌کند |
| اطلاعات ویدیو | عنوان، کانال، مدت و بندانگشتی خودکار در نشانک پر می‌شود؛ پیشرفت دانلود زنده نمایش داده می‌شود |
| تشخیص خودکار | نشانک‌های یوتیوب/آپارات به‌عنوان «ویدیوی آمادهٔ دانلود» شناخته می‌شوند |

#### بستهٔ خواندن و بایگانی

| بخش | جزئیات |
|---|---|
| نسخهٔ کامل صفحه | متن کامل صفحه هنگام افزودن آرشیو می‌شود (قابل خاموش کردن) — حتی اگر سایت رفت، متن می‌ماند |
| جستجوی عمیق | متن آرشیو‌شده داخل ایندکس FTS5 است؛ جستجو به **محتوای صفحات** هم می‌رسد |
| عکس واقعی صفحه | با WKWebView از بالای صفحه عکس گرفته می‌شود و در کارت‌ها/باکس‌ها جای فاوآیکون را می‌گیرد (تشخیص خودکار عکس خالی/صفحهٔ خطا) |

#### بستهٔ دستیار هوشمند

| بخش | جزئیات |
|---|---|
| اتصال پروایدر | **پروتکل سازگار با OpenAI (`/v1`)** — آدرس سرویس، کلید و مدل را هر کاربر خودش در «تنظیمات ← دستیار هوشمند» انتخاب می‌کند (با دکمهٔ «تست اتصال») |
| گفتگو دربارهٔ لینک | با **یک یا چند لینک** دربارهٔ محتوایشان صحبت کن و مشاوره بگیر؛ دکمهٔ ✦ در سربرگ هر نشانک (یا **⌘⇧D**) → پنل گفتگو |
| پرسش‌های سریع | «به درد من می‌خورد؟»، «خلاصهٔ ۵ نکته‌ای»، «مزایا و معایب»، «ریسک‌ها و نکات منفی»، «مقایسه با نیاز و بودجهٔ من»، «سؤال‌های قبل از خرید» + گفتگوی آزاد |
| پرسش از کل کتابخانه | چت نوع «کتابخانه»: پرسش آزاد از میان همهٔ نشانک‌ها با **ارجاع شماره‌دار** ([۱]، [۲]…) و تراشه‌های قابل‌کلیک |
| زمینهٔ پاسخ | متن ذخیره‌شدهٔ صفحه + عنوان/آدرس/یادداشت/برچسب‌ها + پروفایل شما؛ اگر متن از قبل ذخیره نشده باشد، دستیار **هنگام نخستین پرسش خودش صفحه را می‌خواند** |
| صداقت پاسخ | قیمت/موجودی فقط اگر در صفحه آمده گفته می‌شود («طبق همین صفحه»)؛ اطلاعات ناقص حدس زده نمی‌شود |
| حریم خصوصی | فقط متن همان نشانکِ انتخاب‌شده و پروفایلی که خودتان نوشته‌اید ارسال می‌شود؛ کلید فقط در همین مک نگه داشته می‌شود |

#### بستهٔ گفتگو، حافظه و بازیابی

| بخش | جزئیات |
|---|---|
| صفحهٔ گفتگوها | **⌘⇧C** یا دکمهٔ 💬 در نوار ابزار: همهٔ چت‌ها با جستجو، زمان، پیش‌نمایش و شمار پیام — ادامه، تغییر نام، سنجاق، **شروع از نو** (پاک کردن پیام‌ها) و حذف |
| چت پایدار برای هر نشانک | گفتگوی هر نشانک ذخیره می‌شود؛ هر وقت خواستی از همان پنل دستیار (✦ یا **⌘⇧D**) ادامه بده |
| لاگ تصمیم | زیر پاسخ دستیار یا از منوی گفتگو: «خریدم / نخریدم / فعلاً نه» + یادداشت؛ تصمیم‌ها با تاریخ ذخیره و در برچسب سربرگ نشانک دیده می‌شوند |
| صفحهٔ امروز | **⌘⇧T**: «امروز بخوان»، «تازه‌های امروز»، «دوباره ببین» (فراموش‌شده‌های دو ماه پیش) و **بازبینی تصمیم‌های قدیمی** («هنوز همین نظرم؟») |
| پالت فرمان | **⌘K**: دستورها، پرش به پوشه/برچسب/محدوده، جستجوی نشانک و گفتگو، و «از کتابخانه بپرس: …» — همه از یک کادر |
| فیلترهای ذخیره‌شده | جستجو + محدوده + مرتب‌سازی فعلی را با نام ذخیره کنید؛ کلیک = اعمال (در سایدبار و منوی «بیشتر») |
| تکراری‌یاب | نرمال‌سازی آدرس (http/https، www، پارامترهای ردیابی) و حذف نسخه‌های اضافه (نسخهٔ جدیدتر نگه داشته می‌شود) |
| گروه‌بندی فهرست | بدون گروه / بر اساس دامنه / ماه شمسی / پوشه (با شمارش هر گروه) |
| ظاهر پوشه | رنگ (۱۰ رنگ پالت) و آیکون سفارشی (۱۶ نماد) برای هر پوشه — راست‌کلیک روی پوشه |

#### بستهٔ زیبایی و پلتفرم

| بخش | جزئیات |
|---|---|
| طراحی رابط | **۶ چیدمان کامل** به انتخاب کاربر — **کلاسیک** (سه‌ستونهٔ مک)، **شفق/Aurora** (تب‌بار شیشه‌ای و کارت‌های تصویری)، **تمرکز/Focus** (تک‌ستون تایپوگرافیک)، **داشبورد/Dashboard** (کارت‌های آمار و ابر برچگ)، **آرشیو/Atlas** (کاتالوگ کتابخانه با تایپ سریف)، **مدار/Orbit** (لانچر تایل‌بزرگ). همهٔ دسترسی‌ها در هر طراحی موجود است |
| رنگ برنامه | ۱۰ رنگ تم + «پیش‌فرض» (رنگ سیستم) — روی هر طراحی اثر می‌گذارد |
| تمپلیت رنگی | ۶ تم (کلاسیک، نیمه‌شب، اقیانوس، جنگل، غروب، شکوفه) با گرادیان و حالت روشنایی خودش |
| حالت روشنایی | هماهنگ با سیستم / روشن / تاریک |
| چگالی فهرست | فشرده / راحت (اندازهٔ سطر و فاصله‌ها) |
| نوار منو | دسته‌بندی نتایج **بر اساس پوشه** + جستجوی سریع + افزودن از کلیپ‌بورد |
| پنجرهٔ تنظیمات | عمومی، ظاهر (طراحی چیدمان + تم + رنگ)، آرشیو متن، **دستیار هوشمند**، داده‌ها، آمار، درباره |

#### میان‌برها

| کلید | کار |
|---|---|
| ⌘N | نشانک جدید |
| ⌘⇧Space | افزودن سریعٔ سراسری (در هر برنامه) |
| ⌘⇧K | افزودن سریع (از منوی برنامه) |
| ⌘⇧N | پوشهٔ جدید |
| ⌘⇧D | دستیار دربارهٔ نشانک انتخاب‌شده |
| ⌘K | پالت فرمان (دستور، جستجو، پرسش) |
| ⌘⇧C | صفحهٔ گفتگوها |
| ⌘⇧T | صفحهٔ امروز |
| ⌘F | جستجو |
| ⌘V | چسباندن آدرس + افزودن سریع (وقتی فیلد متنی فعال نیست) |
| ⌘Z | بازگردانی آخرین حذف |
| ⌘⌫ | حذف انتخاب (به زباله‌دان) |
| ⌘↩ | باز کردن / ذخیره |

</div>

### معماری

```
Sources/NeshankYar/
  App/NeshankYarApp.swift      ورودی، پنجره، نوار منو، باکس منوبار، فرمان‌ها، مانیتور کلید
  Store/Database.swift         پوشش نازک SQLite (prepared statement، پارامترهای امن)
  Store/Library.swift          منطق اصلی + وضعیت رابط (@MainActor ObservableObject)
  Models/Models.swift          Bookmark/Folder/Tag، نرمال‌سازی آدرس، تاریخ و اعداد فارسی
  Models/Settings.swift        تنظیمات ظاهری (تم، چگالی، گروه‌بندی، میان‌بر) + رنگ HEX
  Services/PageMeta.swift      دریافت عنوان/توضیح/og:image/آیکون + متن کامل صفحه
  Services/HTMLText.swift      استخراج متن خوانا از HTML (برای آرشیو و جستجوی عمیق)
  Services/Screenshotter.swift عکس واقعی صفحه با WKWebView
  Services/HotKey.swift        میان‌بر سراسری با Carbon (بدون مجوز)
  Services/LinkChecker.swift   سلامت لینک (alive/dead/unknown)
  Services/ImportExport.swift  پارسر و تولیدکنندهٔ HTML مرورگرها
  Services/AIClient.swift      اتصال پروایدر سازگار با OpenAI (‎/v1)
  Services/YtDlp.swift         اجرای yt-dlp باندل‌شده + پارس پیشرفت/متادیتا
  Views/                       ریشه، سایدبار، فهرست، جزئیات، ویرایشگر، نوار منو،
                               تنظیمات، پنل افزودن سریع، ابزار نقشهٔ ذهنی، ابزار دانلودر، چت‌ها
  Views/Designs/               پوسته‌های طراحی: Aurora/Focus/Dashboard/Atlas/Orbit + UIDesign
  Resources/MindMap/canvas.html  بوم رندر نقشهٔ ذهنی (خودکفا، آفلاین)
  Resources/Extractor/         Readability.js + Turndown.js (همراه مجوز خودشان)
Scripts/
  build_app.sh                 ساخت .app + ICNS + امضای ad-hoc + DMG
  run_tests.sh                 مجموعهٔ تست (۵۷ بررسی)
```

### تست لایهٔ منطق و ایمنی داده

```bash
Scripts/run_tests.sh
```

**۵۷ تست:** نرمال‌سازی آدرس، سلامت دیکشنری بومی‌سازی، مهاجرت اسکیما، بک‌آپ‌گیری (اسنپ‌شات، شکست منبع ناموجود، هرس روزانه)، عملکرد نقشه‌های ذهنی و سلامت طراحی‌های رابط. خروجی ۱ یعنی شکست (مناسب CI).

### نکات

- امضای برنامه ad-hoc است؛ برای توزیع باید با گواهی توسعه‌دهندهٔ اپل امضا شود.
- بدون اینترنت هم کامل کار می‌کند؛ فقط دریافت اطلاعات صفحه، عکس صفحه، بررسی لینک، دریافت هوش مصنوعی و دانلود ویدیو به شبکه نیاز دارد.
- داده‌های شما دست‌نخورده می‌ماند؛ مهاجرت پایگاه داده خودکار و بدون پاک کردن انجام می‌شود.

### تشکر

- [mind-elixir](https://github.com/SSShooter/mind-elixir-core) (MIT) — بنیان اولیهٔ نقشهٔ ذهنی راست‌به‌چپ
- [Mozilla Readability](https://github.com/mozilla/readability) (Apache-2.0) — استخراج مقاله برای آرشیو صفحه
- [Turndown](https://github.com/mixmark-io/turndown) (MIT) — تبدیل HTML به مارک‌داون
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — موتور دانلود باندل‌شده داخل برنامه
- [ffmpeg-static](https://github.com/eugeneware/ffmpeg-static) · [deno](https://github.com/denoland/deno) · [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider)

### مجوز

[MIT](./LICENSE) © hosein shahraki — ابزارها و کتابخانه‌های باندل‌شده مجوز خودشان را دارند.

---

## Русский

**Neshank** — нативный, полностью офлайн **менеджер закладок для macOS** с AI-чатом, картой мыслей и встроенным видеозагрузчиком. Бесплатный, с открытым исходным кодом (MIT), SwiftUI + SQLite — для сборки Xcode не нужен.

| Возможность | Описание |
|---|---|
| 📦 Быстрое добавление из меню строки | Сохранение ссылки в один клик; глобальная горячая клавиша **⌘⇧Space** вызывает панель быстрого добавления из любого приложения (без доступа к «Специальным возможностям») |
| 🗂️ Организация и поиск | Папки, теги, **полнотекстовый поиск** (включая сохранённый текст страниц — SQLite FTS5), скриншоты страниц, проверка битых ссылок, корзина ⌘Z, импорт/экспорт Safari/Chrome/Firefox |
| 🤖 AI-чат | Любой провайдер, совместимый с OpenAI `/v1` (OpenAI, OpenRouter, локальный **Ollama**) — вопросы по одной ссылке или всей библиотеке с нумерованными цитатами [1] [2]; настроено под **маленькие и бесплатные модели** |
| 🧠 Ссылка → карта мыслей | **6 шаблонов вёрстки**, несколько цветовых тем, полностью офлайн; живые виды: карта / дерево / Markdown / JSON |
| ⬇️ Встроенный загрузчик видео | **YouTube, Aparat, SoundCloud, TikTok, Dailymotion и ещё 1700+ сайтов** (встроенный yt-dlp), без настроек и без аккаунта; в v1 — до 720p |
| 🔒 Приватность | Полностью офлайн: без аккаунта, без облака, без телеметрии — данные остаются на вашем Mac |

**Горячие клавиши:** ⌘N — новая закладка · ⌘⇧Space — быстрое добавление (глобально) · ⌘K — палитра команд · ⌘⇧D — AI-ассистент · ⌘⇧T — «Сегодня» · ⌘⇧C — чат · ⌘F — поиск

**Установка:** скачайте `Neshank-1.dmg` на странице [Releases](../../releases/latest) → откройте → перетащите в «Программы». При первом запуске: **правый клик → Открыть** (ad-hoc подпись). Требования: **macOS 13+, Apple Silicon**.

[English](#english) · [简体中文](#chinese) · [فارسی](#persian)
