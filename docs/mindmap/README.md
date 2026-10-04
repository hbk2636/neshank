# Mind Map Designer

Turn any saved link — or the page you are looking at — into a **visual mind map**,
fully offline. This guide describes the feature as shipped in **Neshank v1.0**.

<p align="center">
  <img src="../assets/screenshot-mindmap.png" width="820" alt="Mind Map Designer — six layouts, ten color themes, four live views">
</p>

## Opening the tool

| Route | How |
|-------|-----|
| Sidebar | **Tools → Mind Map Designer** |
| Command palette | Press **⌘K**, type *mind map* |
| Tools menu | **⋯ → Tools → Mind Map Designer** in every UI shell |
| Selected bookmark | The tool opens with the selected bookmark's URL pre-filled |

The designer is a **separate, resizable native window** (default 1000×720, minimum
760×560) so you can keep your library visible while you work on a map.

## The pipeline (5 steps)

Paste a URL (or start from a bookmark) and press **Start**. The tool walks five
explicit steps, each shown with pending / running / success / failed state:

1. **Fetch Page** — the page is opened in an isolated `WKWebView` (no scripts from the
   page can touch your data) and the DOM is allowed to settle before extraction.
2. **Extract Main Content** — Mozilla **Readability** picks the article body; if it
   fails, a region-based fallback selector runs. The result is scored by a
   [quality gate](#quality-gate) before anything is sent anywhere.
3. **Convert to Markdown** — **Turndown** turns the cleaned HTML into Markdown
   (both libraries are bundled in the app, no CDN, no network call).
4. **AI Analysis** — the Markdown is sent to *your* OpenAI-compatible provider
   (Settings → Assistant). The prompt is engineered for **small and free models**:
   output must be a single raw JSON tree, max depth 4, node text ≤ 15 words,
   navigation/ads/comments stripped.
5. **Build Map** — the JSON is validated, rendered on the offline canvas and stored
   as an independent library record.

If extraction fails or the text is too thin, open **Paste Text Manually** —
give it text and it builds the map from that (the text enters the pipeline at
the AI-analysis step). If the API call fails, an inline **AI setup card** opens
*in the window* with the full setup form (provider address, API key, model).

### Quality gate

The gate rejects thin or noisy pages **before** the AI call, so you never burn tokens
on a menu page:

| Signal | Accepted when |
|--------|---------------|
| Useful characters | ≥ 250, **or** |
| Word count | ≥ 40, **or** |
| Structure | ≥ 1 heading **and** ≥ 2 paragraphs |
| Title-only page | rejected when ≥ 90 % of words overlap the title and < 40 words |
| Menu/list page | rejected when < 40 words, < 5 lines and no headings |

Normalization applied before scoring: Arabic characters folded to their Persian
counterparts (U+064A/U+0649 -> U+06CC, U+0643 -> U+06A9), zero-width and bidi
marks removed, whitespace collapsed — so RTL pages are judged on content, not
encoding artifacts.

## Views

Four tabs (**Mind Map Tab**, **Tree View**, **Source Markdown**, **JSON
Structure**), all live over the same document — switching never reloads or loses
state:

| Tab | Shows |
|-----|-------|
| **Mind Map Tab** | the interactive canvas |
| **Tree View** | outline tree of the same nodes |
| **Source Markdown** | the Markdown the map was built from |
| **JSON Structure** | the raw map JSON (meta + root tree) |

## Canvas

The renderer is a single self-contained file (`canvas.html`) bundled inside the app —
**no remote resources, no Electron, works on a plane**. It only ever receives
JSON-serialized data through a hardened bridge (no raw JavaScript, HTML-escaped):

- **Pan** with either mouse button · **zoom** with ⌘/Ctrl + scroll
- **Drag nodes freely** to re-arrange · **double-click** to rename
- **Collapse / expand** branches · **search** across the map
- Layout is applied server-side-in-canvas: `tree`, `org`, `radial`, `outline`,
  `timeline` and the balanced two-sided `mindmap`

## Layouts, themes and direction

**6 layouts** — *Horizontal Tree* · *Organizational (Vertical)* · *Radial* ·
*Outline* · *Timeline (Top–Bottom)* · *Mind Map (Two-Sided)* (the balanced
Buzan/XMind style with the root in the center and branches alternating left/right).

**10 color themes** — `light` `dark` `forest` `ocean` `sunset` `lavender` `mono`
`sand` `sakura` `mint`. Dark/light is mapped automatically with the system
appearance.

**Direction** — *Root Left (Default)* / *Root Right*. Right-to-left languages pick
*Root Right* automatically and render node text with `dir="rtl"` while the document
itself stays LTR (no mirrored controls).

All three live in the **Mind Map Templates** menu (🎨) as one-click sections —
layout, color theme and root direction.

## Saving and exporting

**Save** (the download-style button in the toolbar) stores the map as an **independent record
in the library** — it does not modify the bookmark it came from. Saved maps open from
the *Mind Maps* view of your library with node counts, and they are included in daily
backups.

**Export** menu:

| Format | Notes |
|--------|-------|
| **JSON File** | the raw map document (meta + tree) |
| **Markdown File** | outline Markdown |
| **PNG Image** | snapshot of the canvas |
| **JPEG Image** | snapshot of the canvas |
| **Standalone HTML Page** | single self-contained file — data injected via `JSON.parse` + an auto-call wrapper, HTML-escaped, **zero remote references**, template never mutated |

File names are sanitized (forbidden characters replaced, empty title falls back to
`mindmap`, capped at 60 characters).

## Storage

Maps live in the local SQLite database (`mind_maps` table), **separate from
bookmarks**:

- `node_count` is stored on write, so the library list renders without parsing JSON
- a `content_hash` is recorded on every map (the hook for future content caching)
- schema is versioned (`user_version`) and migrated forward without wiping data
- daily automatic backups cover maps together with the rest of the library

## Testing

```bash
zsh Scripts/run_tests.sh
```

The suite asserts, among others (see `Tests/NeshankTest/main.swift`):

- layout/theme integrity: all 6 layouts and 10 themes are defined with non-empty
  labels, and the canvas must recognize the `mindmap` layout, its balanced-layout
  function, its opposing links and the outline markers
- balanced two-sided layout really produces opposing links and a center root
- outline layout aligns the left edge and uses vertical connectors
- template menu, direction raw values and theme→appearance mapping
- `node_count` correctness on insert/update and JSON round-trip of saved maps

## Troubleshooting

| Symptom | What to do |
|---------|------------|
| *AI setup card* in the window | Your provider is missing/unreachable — fill the form in the card (or Settings → Assistant) and press **Test Connection** |
| *Text quality too low* | Use **Paste Text Manually**, or open the page and re-try after it fully loads |
| *Render error* label in the tab bar | The map JSON was invalid — press **Start** again to regenerate |
| Map looks empty | Zoom to fit (toolbar), check collapsed branches, try another layout |
