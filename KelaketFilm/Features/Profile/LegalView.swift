import SwiftUI

/// Terms of use and privacy policy, shown inside the app instead of the
/// site's pages (mizbancinema.ir/rules and /privacy-policy). The English app
/// gets an English translation; `{app}` is the app's name.
struct LegalView: View {
    enum Kind { case rules, privacy }

    let kind: Kind

    private struct Part: Hashable {
        let heading: String?
        let body: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(parts, id: \.self) { part in
                    VStack(alignment: .leading, spacing: 8) {
                        if let heading = part.heading {
                            Text(heading).font(.headline)
                        }
                        Text(part.body)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .multilineTextAlignment(.leading)
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("legal")
    }

    private var title: String {
        switch kind {
        case .rules: return L("قوانین و مقررات", "Terms of use")
        case .privacy: return L("حریم خصوصی", "Privacy policy")
        }
    }

    private var parts: [Part] {
        let english = Region.isInternational
        let source: [(String?, String)]
        switch kind {
        case .rules: source = english ? Self.rulesEn : Self.rulesFa
        case .privacy: source = english ? Self.privacyEn : Self.privacyFa
        }
        let name = Bundle.main.appName
        return source.map { Part(heading: $0.0?.replacingOccurrences(of: "{app}", with: name),
                                 body: $0.1.replacingOccurrences(of: "{app}", with: name)) }
    }

    // MARK: Texts

    private static let rulesFa: [(String?, String)] = [
        (nil, "به {app} خوش آمدید. استفاده شما از خدمات {app} به معنای مطالعه، آگاهی و پذیرش کامل شرایط و قوانین زیر است. این قوانین جهت حفظ حقوق کاربران و بهبود کیفیت خدمات تدوین شده و رعایت آن برای همه کاربران الزامی است."),
        ("حقوق و مالکیت محتوا", "تمامی فیلم‌ها، سریال‌ها، زیرنویس‌ها و سایر محتوای موجود، از منابع معتبر جمع‌آوری و صرفاً برای استفاده شخصی کاربران قرار داده شده‌اند. هرگونه بازنشر، فروش، کپی‌برداری یا انتشار مجدد محتوا بدون اجازه کتبی از {app} ممنوع بوده و پیگرد قانونی خواهد داشت."),
        ("ثبت‌نام و اطلاعات کاربری", "کاربر موظف است در هنگام ثبت‌نام یا برقراری ارتباط با {app}، اطلاعات صحیح و دقیق ارائه دهد. حفظ و نگهداری از نام کاربری و رمز عبور بر عهده خود کاربر است و {app} هیچ مسئولیتی در قبال سوءاستفاده احتمالی از حساب‌های کاربری نخواهد داشت."),
        ("دانلود و پخش آنلاین", "کلیه لینک‌های دانلود و امکان تماشای آنلاین صرفاً برای استفاده شخصی طراحی شده‌اند. انتشار مجدد لینک‌ها، اشتراک‌گذاری در سایت‌ها و شبکه‌های اجتماعی دیگر یا فروش آن‌ها، خلاف قوانین است و منجر به مسدود شدن دسترسی کاربر می‌شود."),
        ("حریم خصوصی کاربران", "{app} متعهد به حفظ حریم خصوصی و اطلاعات شخصی کاربران است. هیچ‌گونه اطلاعاتی بدون رضایت کاربر در اختیار اشخاص یا نهادهای دیگر قرار نخواهد گرفت، مگر در مواردی که قانون الزام کرده باشد."),
        ("مسئولیت استفاده از خدمات", "تمامی فایل‌ها و لینک‌ها پیش از انتشار بررسی می‌شوند، با این حال مسئولیت استفاده نادرست از فایل‌ها یا مشکلات ناشی از نرم‌افزارها و تجهیزات کاربران، بر عهده خود کاربر خواهد بود. {app} هیچ تعهدی نسبت به خسارت‌های احتمالی ناشی از استفاده نادرست ندارد."),
        ("تغییر قوانین", "{app} ممکن است در بازه‌های زمانی مختلف، قوانین و شرایط استفاده را تغییر دهد. آخرین نسخه قوانین همیشه در همین بخش منتشر می‌شود و استفاده مستمر شما از {app} به معنای پذیرش قوانین جدید است."),
    ]

    private static let rulesEn: [(String?, String)] = [
        (nil, "Welcome to {app}. By using {app} you confirm that you have read, understood and fully accept the terms below. They protect our users' rights and the quality of the service, and apply to everyone."),
        ("Content and ownership", "All movies, series, subtitles and other content are gathered from reliable sources and provided for personal use only. Republishing, selling, copying or redistributing any content without written permission from {app} is prohibited and may lead to legal action."),
        ("Account and personal details", "When you sign up or contact us, you must provide accurate and correct information. You are responsible for keeping your username and password safe; {app} is not responsible for any misuse of your account."),
        ("Downloads and streaming", "All download links and online playback are for personal use only. Republishing links, sharing them on other websites or social networks, or selling them is against these terms and will result in your access being blocked."),
        ("Privacy", "{app} is committed to protecting your privacy and personal information. No information is shared with other people or organisations without your consent, except where required by law."),
        ("Use of the service", "All files and links are checked before they are published. However, you are responsible for any misuse of the files and for problems caused by your own software or devices. {app} accepts no liability for damage resulting from improper use."),
        ("Changes to these terms", "{app} may change these terms from time to time. The latest version is always published here, and continuing to use {app} means you accept the updated terms."),
    ]

    private static let privacyFa: [(String?, String)] = [
        (nil, "در این بخش توضیح می‌دهیم که چه اطلاعاتی از کاربران جمع‌آوری می‌شود و {app} با این اطلاعات چگونه برخورد می‌کند. {app} همواره اصول محرمانگی را در مورد اطلاعات شخصی کاربران رعایت کرده و از این اطلاعات به نحو احسن محافظت می‌نماید."),
        ("اشخاص ثالث", "{app} اطلاعات شخصی کاربران را در اختیار اشخاص ثالث قرار نخواهد داد، به‌استثنای مواردی که به‌موجب قانون موظف به انجام این کار باشد. چنانچه این اطلاعات به‌صورت غیرعمد یا بدون اطلاع و رضایت ما در دسترس شخص ثالثی قرار گیرد، {app} مسئولیتی نخواهد داشت."),
        ("اطلاعاتی که در اختیار ما قرار می‌دهید", "در فرآیند ثبت‌نام، اطلاعات کاربر شامل نام و نام خانوادگی، آدرس ایمیل و شماره تلفن همراه دریافت می‌شود و در پایان ایمیلی جهت احراز هویت به آدرس ایمیل اعلام‌شده فرستاده می‌شود. پس از ثبت‌نام، اطلاعاتی از قبیل «فیلم‌های خریداری‌شده»، «ویرایش مشخصات»، «فیلم‌های دیده‌شده» و «سوابق پرداخت» در حساب شما نمایش داده می‌شود. در بخش ویرایش مشخصات می‌توانید در صورت تمایل نام، شماره تلفن همراه، نام کاربری و ایمیل خود را به‌روزرسانی کنید."),
        ("استفاده از اطلاعات", "{app} اطلاعاتی را که از حساب کاربران به طور خودکار به دست می‌آید، جهت تحلیل، بررسی و شخصی‌سازی خدمات خود و ارائه پیشنهادهای نزدیک‌تر به سلیقه کاربران استفاده می‌کند. این اطلاعات به ما کمک می‌کند سرویس را بهبود بخشیم و محتوای مرتبط‌تری با علایق هر کاربر ارائه کنیم. {app} این اختیار را دارد که هنگام پخش فیلم، به فراخور زمان و محتوا، تبلیغ نمایش دهد."),
        ("اطلاع‌رسانی", "{app} برای ارائه بهتر خدمات و اطلاع‌رسانی درباره طرح‌های ویژه و فیلم‌های جدید ممکن است از طریق ایمیل یا شماره تلفن همراه ثبت‌شده برای شما پیام بفرستد. همیشه می‌توانید با دکمه لغو اشتراک در انتهای ایمیل‌ها، آن‌ها را غیرفعال کنید."),
    ]

    private static let privacyEn: [(String?, String)] = [
        (nil, "This page explains what information we collect from users and how {app} handles it. {app} always respects the confidentiality of your personal information and protects it as well as it can."),
        ("Third parties", "{app} does not share users' personal information with third parties, except where the law requires it. {app} is not responsible if this information becomes available to a third party unintentionally or without our knowledge and consent."),
        ("Information you give us", "When you sign up, we receive your first and last name, email address and mobile number, and send an email to that address to verify your account. Once signed up, your account shows information such as purchased titles, profile details, watched titles and payment history. In your profile settings you can update your name, mobile number, username and email at any time."),
        ("How we use information", "{app} uses information gathered automatically from accounts to analyse, review and personalise its service and to offer suggestions closer to your taste. This helps us improve the service and show each user more relevant content. {app} may show advertisements during playback, depending on the time and content."),
        ("Notifications", "To improve the service and tell you about special offers and new titles, {app} may send you messages by email or to your registered mobile number. You can always turn these emails off with the unsubscribe button at the end of each email."),
    ]
}
