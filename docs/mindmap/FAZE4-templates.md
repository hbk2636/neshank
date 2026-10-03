# FAZE4 — چیدمان «نقشهٔ ذهنی (دوطرفه)» + فیکس کرش تعویض تب

## باگ ۱ — کرش/گیر با تعویض تب (بازتولیدشده با هارنس)
- **نشانه**: بعد از جنریت، رفتن به نمای درختی/مارک‌داون/JSON و برگشت به نقشه → اسپینر «در حال رندر» ابدی (nodes=0 برای همیشه، بدون خطا).
- **ریشه** (لاگ هارنس `MMTAB`): با تعویض تب، `MindMapWebView` نابود و وب‌ویوی تازه ساخته می‌شد؛ `updateNSView` قبل از `didFinish` اجرا می‌شد (`loaded=false` → رندر رها می‌شد و JSON هم ذخیره نمی‌شد) و بعد از `didFinish` هیچ‌چیز رندر را دوباره تریگر نمی‌کرد. رندر گم می‌شد.
- **فیکس سه‌لایه**:
  1. `MindMapWebView.updateNSView`: اگر صفحه هنوز بار نشده، JSON با `bridge.stagePending()` نگه داشته می‌شود تا `didFinish` رندرش کند (متد جدید `stagePending` در `MindMapRenderBridge`).
  2. حذف رندر تکراری `.onChange(of: model.mapJSON)` در `MindMapToolView` (منبع چرخهٔ «رندر → به‌روزرسانی → رندر»)؛ فقط `clear` و سینک `layoutName` ماند.
  3. هر چهار تب (`map/tree/markdown/json`) حالا همیشه زنده‌اند (ZStack + opacity) — وب‌ویو با تعویض تب اصلاً نابود نمی‌شود؛ برگشت آنی، بدون ریلود.
- **تأیید**: هارنس `NESHANK_OPEN_MINDMAP=1 NESHANK_MINDMAP_TABS=1` — قبل: `nodes=0` ابدی؛ بعد: `nodes=10` در همهٔ تب‌ها و همهٔ برگشت‌ها.

## تغییر ۲ — قالب قدم قبل حذف، چیدمان استاندارد اضافه شد
- گالری «سگ‌ها (نقشهٔ نمونه)» از صفحهٔ آماده + `loadTemplate` + `MindMapTemplates.swift` + ۴ رشتهٔ لوکال + تست‌هایش **کاملاً حذف** شد (اشتباه جا بود؛ نامش هم علمی نبود).
- به‌جاش در **منوی انواع چیدمان** گزینهٔ ششم آمد: `mindmap` با نام استاندارد سبک بوزان/XMind — «نقشهٔ ذهنی (دوطرفه)» / `Mind Map (Two-Sided)`: ریشه وسط، شاخه‌های اصلی یکی‌درمیان راست و چپ، نسل‌ها به بیرون. دکمهٔ «جهت ریشه» دو طرف را آینه می‌کند.
- برچسب قدیمی `Two-Sided (Timeline)` که حالا تداخل معنایی داشت، به `Timeline (Top–Bottom)` / «خط زمانی (بالا–پایین)» تغییر کرد (تایم‌لاین واقعاً بالا/پایین است، نه چپ/راست).
- سیم‌های روبه‌رو (`anchor(p, true, n)`) که برای همین کار لازم بود، در بوم هست و روی همهٔ چیدمان‌های خودکار قبلی بی‌اثر است.

## راستی‌آزمایی (۲۰۲۶-۱۰-۰۱)
- `swift build` سبز؛ `run_tests.sh`: **۵۵/۵۵** (بخش ۶ جدید: enum/بوم هم‌نام، ۶ آیتم منو، تابع `layoutBalanced`، سیم روبه‌رو).
- رندر واقعی headless + `setLayout('mindmap')`: ‎۱۴ کارت، ۱۳ سیم، **۰ هم‌پوشانی**، `twoSided:true`، ماندگاری `layout=mindmap` در JSON.
- فایل‌ها: `Resources/MindMap/canvas.html` (+`layoutBalanced`/`mindmap`)، `Services/MindMapExport.swift` (+case/icon/label)، `Models/Localization.swift` (+۲ ورودی ۴زبانه، −۴ ورودی قالب، بازنویسی ۲ ورودی)، `Views/MindMapToolView.swift` (تب‌های ماندگار + حذف گالری + راهنمای منو)، `Views/MindMapWebView.swift` (+`stagePending`)، `Views/MindMapToolModel.swift` (−`loadTemplate`)، `App/NeshankYarApp.swift` (+هارنس `NESHANK_OPEN_MINDMAP`/`NESHANK_MINDMAP_TABS`)، `Tests/NeshankTest/main.swift` (بخش ۶ جدید).
