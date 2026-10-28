# کلاکت فیلم — نسخه iOS

اپ نیتیو iOS (SwiftUI، حداقل iOS 16) که به همان API افزونه‌های وردپرسی `kelaketfilm-app`، `kelaketfilm-jwt` و `kelaketfilm-otp` وصل می‌شود؛ بنابراین سمت سرور تغییری لازم ندارد.

## راه‌اندازی

1. در [Config/Config.xcconfig](Config/Config.xcconfig) مقادیر زیر را تنظیم کنید:
   - `KF_SITE_HOST`: دامنه سایت، بدون `https://` (مثلاً `kelaketfilm.ir`)
   - `KF_API_KEY`: همان API Key تنظیمات افزونه اپ
   - `KF_BUNDLE_ID` و `KF_TEAM_ID`: برای امضا و انتشار
2. ساخت پروژه Xcode (روی مک):
   ```bash
   brew install xcodegen
   xcodegen generate
   open KelaketFilm.xcodeproj
   ```
3. بدون مک: با push کردن روی GitHub، ورک‌فلوی [.github/workflows/ios-build.yml](.github/workflows/ios-build.yml) روی macOS بیلد می‌گیرد. برای خروجی IPA امضاشده باید گواهی و پروفایل اپل را به‌صورت Secret اضافه کنید (یا از Codemagic استفاده کنید).

## ساختار

| مسیر | توضیح |
|---|---|
| `KelaketFilm/Core/Network` | کلاینت API؛ هدرهای `X-API-KEY`، `X-USER-TOKEN`، `X-KELAKET-CLIENT: ios` |
| `KelaketFilm/Core/Models` | مدل‌ها. فیلدهای ACF با تایپ نامنظم (`false`، عدد/رشته، `[]`) با wrapperهای `Lossy*` خوانده می‌شوند |
| `KelaketFilm/App` | ورودی اپ، تب‌ها، `AppState` (کانفیگ، توکن در Keychain، وضعیت اشتراک) |
| `KelaketFilm/Features` | صفحات: ورود، خانه، جستجو، جزئیات فیلم/سریال، پلیر، پروفایل |

## فاز ۱ (انجام شده)

- دریافت کانفیگ (`mobile/v2/config`) و پیام مدیر
- ورود با OTP (`mobile/v1/auth`) و ورود با رمز (`mobile/v2/loginByUsernameEmailPhone`)، ثبت‌نام، روش دوم ورود طبق تنظیمات
- صفحه اصلی (`mobile/v2/home_screen`): اسلایدر، ادامه تماشا، سریال‌های به‌روز، دسته‌ها
- جستجو (`mobile/v1/search`)
- جزئیات فیلم/سریال (`mobile/v2/film/{id}`): کیفیت‌ها، فصل و قسمت، بازیگران، مشابه، کالکشن
- پلیر AVPlayer با PiP و ذخیره پیشرفت تماشا (`mobile/v2/watch_progress/save`)
- محدودیت VIP سمت کلاینت طبق `vip_lock`

## فاز ۲ (انجام شده)

- لیست تماشا: دکمه نشان‌گذاری در صفحه فیلم (`add_watchlist`) و صفحه لیست در پروفایل (`get_watchlist`)
- اطلاع از قسمت جدید سریال (`set_post_notification`)
- رأی مثبت/منفی به فیلم (`setVote`)
- نظرات: پیش‌نمایش در صفحه فیلم، صفحه کامل با صفحه‌بندی، ارسال نظر و پاسخ، اسپویل، لایک و دیسلایک (`get_comments`، `send_comment`، `comments_like_dislike`)
- پشتیبانی: لیست تیکت‌ها، تیکت جدید با دپارتمان، گفتگو (`tickets`، `tickets_msg`، `send_ticket`، `send_ticket_message`)
- درخواست فیلم و لیست درخواست‌ها (`sendRequest`، `requests`)
- لیست اعلان‌ها و علامت خوانده‌شده (`get_notifications`، `set_notification_status`)
- پوش نوتیفیکیشن با Firebase و لینک‌های `kelaketfilm://app/film/{id}`
- نمایش آیتم‌های پروفایل طبق تنظیمات افزونه (`kelaketapp_show_mylist`، `profile_show_tickets`، `profile_show_request_film`) و شرط اشتراک برای تیکت و درخواست

### راه‌اندازی پوش نوتیفیکیشن

افزونه پیام‌ها را با FCM HTTP v1 و بلوک `notification` می‌فرستد. FCM همین پیام را از طریق APNs به آیفون هم می‌رساند، پس تغییری در سرور لازم نیست:

1. در Firebase Console، در همان پروژه اپ اندروید، یک اپ iOS با همان Bundle ID اضافه کنید.
2. فایل `GoogleService-Info.plist` را دانلود کنید و در `KelaketFilm/Resources/` بگذارید، سپس دوباره `xcodegen generate` بزنید.
3. در Project Settings > Cloud Messaging کلید APNs (فایل `.p8` از حساب Apple Developer) را آپلود کنید.
4. در `KF_PUSH_TOPICS` تاپیک‌هایی را بنویسید که در پنل «ارسال اعلان» افزونه استفاده می‌کنید.

تا وقتی این فایل اضافه نشود، Firebase غیرفعال می‌ماند و بقیه اپ عادی کار می‌کند.

## فاز ۳ (انجام شده)

- تب «کاوش» با دسترسی به همه بخش‌ها و شبکه ژانرها (`fetchGenres`)
- آرشیو با فیلتر نوع، ژانر، سال، کشور و مرتب‌سازی (`archive`، `searchTerms`)؛ ژانرهای صفحه فیلم هم به آرشیو لینک شده‌اند
- میان‌برهای «آیتم‌های منوی سفارشی» افزونه (`custom_menu_list`) زیر اسلایدر صفحه اصلی
- صفحه بازیگر با بیوگرافی و آثار (`actorWorks`) و آرشیو بازیگران با جستجو (`actors/archive`)
- باکس‌آفیس (`get_boxoffice`)، برنامه پخش هفتگی (`getWeeklySeries`)، ۲۵۰ برتر فیلم و سریال (`lists/top250`)، کالکشن‌ها (`lists/collections`)
- لیست‌های کاربران: لیست‌های عمومی، لیست‌های من (ساخت، ویرایش، حذف، حذف عنوان) و «افزودن به لیست» از صفحه فیلم (`lists/*`)
- نمایش بخش‌ها طبق تنظیمات افزونه (`show_weekly`، `kelaketapp_show_boxoffice`، `kelaketapp_show_actors_archive`)

**نیاز به بررسی:** کلیدهای روزهای برنامه پخش در تنظیمات پوسته (`series_tabbed`) تعریف شده‌اند، نه در افزونه. اپ از `saturday` تا `friday` استفاده می‌کند؛ اگر پوسته کلید دیگری دارد، آرایه `days` را در `Features/Explore/ChartViews.swift` تغییر دهید.

## فاز ۴ (انجام شده)

- تب «وبلاگ» وقتی `active_blog` روشن است: فهرست مطالب و متن کامل با مطالب مرتبط (`blog/list`، `blog/single`)
- ویرایش پروفایل: نام، ایمیل، رمز عبور جدید و انتخاب آواتار پیش‌فرض (`editUser`، `avatar/options`). تغییر رمز همه توکن‌ها را باطل می‌کند، پس اپ بعد از آن کاربر را خارج می‌کند
- «رمز را فراموش کرده‌اید؟» در فرم ورود با رمز (`resetpass`)
- کیف پول (`wallet`)، دعوت از دوستان با کد و لینک قابل اشتراک (`referral`) و تراکنش‌های اشتراک (`vip/getTransactions`)، طبق `wallet_enabled`، `referral_enabled` و `kelaketapp_show_trans`
- دستگاه‌های فعال با خروج تکی (کشیدن به چپ) و خروج از همه (`active-sessions`)، طبق `profile_show_active_session`

**نیاز به بررسی:** ستون‌های ردیف‌های کیف پول، معرفی و تراکنش‌ها را کلاس‌های پوسته (`Kelaket_Wallet`، `Kelaket_Referral`، `Kelaket_VIP`) می‌سازند که در افزونه نیستند. اپ چند نام رایج را می‌خواند (`Core/Models/Account.swift`) و مبالغ را «تومان» نشان می‌دهد؛ اگر پوسته ریال ذخیره می‌کند یا نام ستون‌ها فرق دارد، همان‌جا اصلاح کنید.

## فاز بعد

- خرید اشتراک: بسته به محل انتشار (پایین را ببینید)
- پخش MKV داخل اپ با VLCKit و زیرنویس SRT، دانلود داخلی

## نکات مهم

**محل انتشار و پرداخت.** اگر اپ در App Store منتشر شود، اپل برای اشتراک VIP پرداخت درون‌برنامه‌ای (StoreKit) را اجباری می‌کند و در افزونه فقط مایکت و بازار پیاده‌سازی شده است. در این حالت باید تأیید رسید اپل به `iap.php` اضافه شود. برای سیب‌اپ، سیبچه و انار دونی می‌توان از همان درگاه بانکی و کیف پول سایت استفاده کرد.

**فرمت ویدیو.** AVPlayer فقط MP4، MOV و HLS را پخش می‌کند. لینک‌های MKV به VLC (اگر نصب باشد) ارجاع داده می‌شوند. زیرنویس جدا (`subtitle` با پسوند `.vtt` یا `.srt`) را خود اپ دانلود می‌کند و روی ویدیو نمایش می‌دهد.
