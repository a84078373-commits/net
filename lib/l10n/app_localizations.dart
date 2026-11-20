import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// App-wide Arabic / English strings. Access via [AppLocalizations.of].
class AppLocalizations {
  AppLocalizations(this.locale);
  final Locale locale;

  static const supportedLocales = [Locale('ar'), Locale('en')];

  static AppLocalizations of(BuildContext context) {
    final l = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(l != null, 'AppLocalizations not found in context');
    return l!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  bool get isArabic => locale.languageCode.toLowerCase() != 'en';
  TextDirection get textDirection =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;

  String _t(String ar, String en) => isArabic ? ar : en;

  // ── Brand & nav ──────────────────────────────────────────────
  String get appTitle => _t('SmartCare • حائل', 'SmartCare • Hail');
  String get navHome => _t('الرئيسية', 'Home');
  String get navStore => _t('المتجر', 'Store');
  String get navQitaf => _t('قطاف', 'Qitaf');
  String get navMore => _t('المزيد', 'More');
  String get brandStc => 'stc';
  String get cancel => _t('إلغاء', 'Cancel');
  String get delete => _t('حذف', 'Delete');
  String get close => _t('إغلاق', 'Close');
  String get allow => _t('السماح', 'Allow');
  String get refresh => _t('تحديث', 'Refresh');
  String get showAll => _t('عرض الكل', 'Show all');
  String get saving => _t('جارٍ الحفظ…', 'Saving…');
  String get analyzing => _t('جارٍ التحليل…', 'Analyzing…');
  String get connecting => _t('جارٍ الاتصال…', 'Connecting…');
  String get analyzeNow => _t('حلّل الآن', 'Analyze now');
  String get signIn => _t('تسجيل الدخول', 'Sign in');
  String get signOut => _t('تسجيل الخروج', 'Sign out');
  String get language => _t('اللغة', 'Language');
  String get languageArabic => _t('العربية', 'Arabic');
  String get languageEnglish => _t('الإنجليزية', 'English');
  String get languageSwitcherHint => _t(
    'اختر لغة واجهة التطبيق',
    'Choose the app interface language',
  );

  // ── Common actions / labels ──────────────────────────────────
  String get settings => _t('الإعدادات', 'Settings');
  String get privacyAndData => _t('الخصوصية وبياناتك', 'Privacy & your data');
  String get myProfile => _t('ملفي الشخصي', 'My profile');
  String get profile => _t('الملف الشخصي', 'Profile');
  String get notifications => _t('الإشعارات', 'Notifications');
  String get saveAndSync => _t('الحفظ والمزامنة', 'Save & sync');
  String get help => _t('المساعدة', 'Help');
  String get privacy => _t('الخصوصية', 'Privacy');
  String get appCenter => _t('مركز التطبيقات', 'App center');
  String get adminDashboard => _t('لوحة تحكم المدير', 'Admin dashboard');
  String get adminPanel => _t('لوحة الإدارة', 'Admin panel');
  String get speedTest => _t('فحص السرعة', 'Speed test');
  String get map => _t('الخريطة', 'Map');
  String get measurementHistory => _t('سجل القياسات', 'Measurement history');
  String get myReports => _t('بلاغاتي', 'My reports');
  String get qualityMap => _t('خريطة الجودة', 'Quality map');
  String get contactUs => _t('تواصل معنا', 'Contact us');
  String get aboutSmartCare => _t('عن SmartCare', 'About SmartCare');
  String get download => _t('التنزيل', 'Download');
  String get upload => _t('الرفع', 'Upload');
  String get httpLatency => _t('استجابة HTTP', 'HTTP latency');
  String get connectionWifi => _t('واي فاي', 'Wi‑Fi');
  String get connectionCellular => _t('خلوي', 'Cellular');
  String get connectionEthernet => _t('سلكي', 'Wired');
  String get unknown => _t('غير معروف', 'Unknown');
  String get enabled => _t('مفعّل', 'Enabled');
  String get stopped => _t('متوقف', 'Stopped');
  String get configured => _t('مضبوط', 'Configured');
  String get notConfigured => _t('غير مضبوط', 'Not configured');
  String get persistent => _t('دائم', 'Persistent');
  String get temporary => _t('مؤقت', 'Temporary');

  // ── Home / mystc ─────────────────────────────────────────────
  String get welcomeToStc => _t('مرحبا بكم في stc', 'Welcome to stc');
  String get searchPlaceholder =>
      _t('ما الذي تبحث عنه؟', 'What are you looking for?');
  String get exploreProducts => _t('استكشف منتجاتنا', 'Explore our products');
  String get productNumberTransfer =>
      _t('حول رقمك إلى stc', 'Transfer your number to stc');
  String get productSimInternet =>
      _t('شريحة جوال وإنترنت', 'Mobile SIM & internet');
  String get joinStc => _t('انضم إلى stc', 'Join stc');
  String get homeInternet => _t('الإنترنت المنزلي', 'Home internet');
  String get quickActions => _t('إجراءات سريعة', 'Quick actions');
  String get quickRecharge => _t('إعادة شحن الرقم', 'Recharge number');
  String get quickUpgradePostpaid =>
      _t('ترقية إلى مفوتر', 'Upgrade to postpaid');
  String get quickMyOrders => _t('طلباتي', 'My orders');
  String get payWithNumber => _t('ادفع برقمك', 'Pay with your number');
  String get demoOnlySnack => _t(
    'هذا العنصر للعرض فقط • الخدمات الفعلية: فحص السرعة وخريطة الجودة',
    'Demo only • Live services: speed test & quality map',
  );
  String get qitafHeaderTitle => _t('قطاف_qitaf', 'Qitaf');
  String get qitafHeroTagline => _t(
    'قيس شبكتك وارسم الجودة على خريطة حائل',
    'Measure your network and map quality across Hail',
  );
  String get qitafOffers => _t('عروض قطاف', 'Qitaf offers');
  String get offerSpeedSubtitle => _t('قياس فعلي', 'Live measurement');
  String get badgeFree => _t('مجاني', 'Free');
  String get offerMapTitle => _t('خريطة الجودة', 'Quality map');
  String get offerMapSubtitle => _t('خلايا حائل', 'Hail cells');
  String get badgeLive => _t('مباشر', 'Live');
  String get offerHistorySubtitle => _t('نتائجك', 'Your results');
  String get badgePrivate => _t('خاص', 'Private');
  String get coverageMap => _t('خريطة التغطية', 'Coverage map');
  String get adminPanelGuest =>
      _t('لوحة الإدارة (دخول المدير)', 'Admin panel (admin sign-in)');
  String get aiAssistTitle =>
      _t('مساعد التحليل الذكي', 'Smart analysis assistant');
  String get networkSpeedTest =>
      _t('فحص سرعة الشبكة', 'Network speed test');
  String get systemAdmin => _t('مدير النظام', 'System admin');
  String adminFullAccessSubtitle(String phone) => _t(
    '$phone • صلاحية مدير كاملة',
    '$phone • full admin access',
  );
  String get openFullAdminPanel =>
      _t('افتح لوحة التحكم الكاملة', 'Open full control panel');
  String get adminPanelBlurb => _t(
    'مستخدمون • قياسات • Gemini • حالة الخادم',
    'Users • measurements • Gemini • server status',
  );
  String get adminSessionActive => _t(
    'جلسة مدير نشطة • اضغط لإدارة الحساب',
    'Admin session active • tap to manage account',
  );
  String get measurementAccountSignedIn =>
      _t('أنت متصل بحساب القياس', 'Signed in to your measurement account');
  String get adminLoginHintPhone =>
      _t('سجّل دخول المدير: 0552515874', 'Admin sign-in: 0552515874');

  // ── More / account ───────────────────────────────────────────
  String get eyebrowSmartcareHail =>
      _t('SMARTCARE / حائل', 'SMARTCARE / Hail');
  String get eyebrowAppCenter => 'APP CENTER';
  String get eyebrowAdminControl => 'ADMIN CONTROL';
  String get eyebrowGemini => 'GEMINI • SERVER KEY';
  String get accountServerSession =>
      _t('حساب SmartCare • الجلسة على الخادم', 'SmartCare account • server session');
  String get guestBrowseBlurb => _t(
    'تصفح كزائر • كل الخدمات في متناولك',
    'Browsing as guest • all services available',
  );
  String get signInOrRegister =>
      _t('تسجيل الدخول / إنشاء حساب', 'Sign in / create account');

  // ── Profile / settings ───────────────────────────────────────
  String get nameLabel => _t('الاسم', 'Name');
  String get nameValidationMin => _t('اكتب اسمك', 'Enter your name');
  String get preferredNeighborhood =>
      _t('الحي المفضل', 'Preferred neighborhood');
  String get browsingAsGuest => _t('تصفح كزائر', 'Browsing as guest');
  String mobileNumberLine(String phone) =>
      _t('رقم الجوال: $phone', 'Mobile number: $phone');
  String get saveChanges => _t('حفظ التعديلات', 'Save changes');
  String get profileUpdatedToast =>
      _t('تم تحديث ملفك الشخصي', 'Your profile was updated');
  String get profileLocalBetaNote => _t(
    'بيانات الملف مرتبطة بهذا المتصفح أو الجهاز في النسخة التجريبية.',
    'Profile data is tied to this browser or device in the demo build.',
  );
  String get inAppNotifications =>
      _t('إشعارات داخل التطبيق', 'In-app notifications');
  String get inAppNotificationsSubtitle => _t(
    'تحديثات البلاغات والقياسات داخل التطبيق',
    'Report and measurement updates inside the app',
  );
  String get autoSaveOnDevice =>
      _t('الحفظ التلقائي على الجهاز', 'Auto-save on device');
  String get autoSaveSubtitle => _t(
    'احفظ البيانات بعد كل تعديل؛ عند إيقافه استخدم الحفظ اليدوي',
    'Save after every change; when off, use manual save',
  );
  String get appearance => _t('المظهر', 'Appearance');
  String get appearanceLightStc =>
      _t('فاتح • هوية stc', 'Light • stc identity');
  String get signedOutToast =>
      _t('تم تسجيل الخروج من هذا الجهاز', 'Signed out on this device');
  String get defaultGuestName =>
      _t('زائر SmartCare', 'SmartCare guest');

  String get neighborhoodMuntazah => _t('المنتزه', 'Al-Muntazah');
  String get neighborhoodNaqrah => _t('النقرة', 'An-Naqrah');
  String get neighborhoodJamiin => _t('الجامعيين', 'Al-Jamiyin');
  String get neighborhoodCentralHail => _t('وسط حائل', 'Central Hail');

  List<String> get neighborhoodsList => [
    neighborhoodMuntazah,
    neighborhoodNaqrah,
    neighborhoodJamiin,
    neighborhoodCentralHail,
  ];

  // ── Auth ─────────────────────────────────────────────────────
  String get registerTitle => _t('إنشاء حساب', 'Create account');
  String get signInTitle => _t('تسجيل الدخول', 'Sign in');
  String get registerHeadline =>
      _t('أنشئ حسابك واحفظ بياناتك', 'Create your account and save your details');
  String get signInHeadline => _t('أهلًا بعودتك', 'Welcome back');
  String get registerSubtitle => _t(
    'يُحفظ الاسم والجنس والرقم وكلمة المرور على خادم SmartCare. بعد الإنشاء تدخل بالرقم وكلمة المرور فقط.',
    'Your name, gender, phone and password are saved on the SmartCare server. After registration, sign in with phone and password only.',
  );
  String get signInSubtitle => _t(
    'الدخول برقم الجوال وكلمة المرور فقط — بدون اسم. الحساب محفوظ على الخادم.',
    'Sign in with mobile number and password only — no name required. Your account is stored on the server.',
  );
  String get firstName => _t('الاسم الأول', 'First name');
  String get secondName => _t('الاسم الثاني', 'Second name');
  String get familyName => _t('اسم العائلة', 'Family name');
  String namePartValidation(String label) => _t(
    'أدخل $label بحروف عربية أو إنجليزية',
    'Enter $label using Arabic or English letters',
  );
  String get gender => _t('الجنس', 'Gender');
  String get genderMale => _t('ذكر', 'Male');
  String get genderFemale => _t('أنثى', 'Female');
  String get genderRequired =>
      _t('اختر الجنس: ذكر أو أنثى', 'Select gender: male or female');
  String get mobileNumber => _t('رقم الجوال', 'Mobile number');
  String get phoneHintSa => '05xxxxxxxx';
  String get phoneValidation => _t(
    'أدخل رقمًا من 10 أرقام يبدأ بـ 05',
    'Enter a 10-digit number starting with 05',
  );
  String get password => _t('كلمة المرور', 'Password');
  String get passwordHelper => _t('6 أحرف على الأقل', 'At least 6 characters');
  String get passwordValidation => _t(
    'استخدم كلمة مرور من 6 أحرف على الأقل',
    'Use a password with at least 6 characters',
  );
  String get createAccountButton =>
      _t('إنشاء الحساب وحفظه', 'Create and save account');
  String get enterButton => _t('دخول', 'Sign in');
  String get switchToSignIn =>
      _t('لديك حساب؟ تسجيل الدخول', 'Have an account? Sign in');
  String get switchToRegister =>
      _t('إنشاء حساب جديد', 'Create a new account');
  String get authSessionFooter => _t(
    'الحساب والجلسة محفوظان على الجهاز والخادم. تبقى مسجّلًا حتى تضغط تسجيل الخروج.',
    'Your account and session stay on this device and the server. You remain signed in until you sign out.',
  );

  // ── Speed test ───────────────────────────────────────────────
  String get internetQualityTestTitle =>
      _t('اختبار جودة الإنترنت', 'Internet quality test');
  String get measurementSectionTitle => _t('القياس', 'Measurement');
  String get speedTestIntro => _t(
    'فحص السرعة مسموح على الواي فاي أو شبكة الجوال. بعد الحفظ تُرسم على الخريطة (طبقة قياساتك) ويُحلَّل بالذكاء الاصطناعي تلقائيًا.',
    'Speed testing works on Wi‑Fi or mobile data. After saving, results appear on your map layer and are analyzed automatically with AI.',
  );
  String get testUnavailableTitle =>
      _t('اختبار الإنترنت غير متاح', 'Internet test unavailable');
  String get testUnavailableDefault =>
      _t('تعذر الوصول إلى خدمة القياس', 'Could not reach the measurement service');
  String get retryCheck => _t('إعادة التحقق', 'Retry');
  String get testConsentTitle =>
      _t('السماح ببدء الاختبار؟', 'Allow starting the test?');
  String get testConsentBodyShare => _t(
    'سيُقاس الاتصال الحالي (واي فاي أو شبكة الجوال) بنقل بيانات فعلية حتى 64 ميبيبايت خلال 90 ثانية، ثم تُحفظ النتيجة تلقائيًا.\n\nسيُطلب الموقع لرسم خلية تقريبية (~1 كم) على الخريطة، دون حفظ إحداثياتك الدقيقة.',
    'Your current connection (Wi‑Fi or mobile) will be measured with real data transfer up to 64 MiB within 90 seconds, then saved automatically.\n\nLocation will be requested to plot an approximate ~1 km cell on the map without storing exact GPS coordinates.',
  );
  String get testConsentBodyNoShare => _t(
    'سيُقاس الاتصال الحالي (واي فاي أو شبكة الجوال) بنقل بيانات فعلية حتى 64 ميبيبايت خلال 90 ثانية، ثم تُحفظ النتيجة تلقائيًا.\n\nلن يُرسم القياس على الخريطة دون مشاركة الموقع.',
    'Your current connection (Wi‑Fi or mobile) will be measured with real data transfer up to 64 MiB within 90 seconds, then saved automatically.\n\nThe result will not be drawn on the map unless location sharing is enabled.',
  );
  String get agreeAndStart => _t('أوافق وأبدأ', 'Agree & start');
  String get phaseReady => _t('جاهز للبدء', 'Ready to start');
  String get phaseLocating =>
      _t('تحديد موقع أدق للخريطة…', 'Getting a more accurate location for the map…');
  String get locationAccuracyInsufficient => _t(
    'دقة الموقع غير كافية للمشاركة • سيُحفظ القياس دون رسم على الخريطة',
    'Location accuracy is too low to share • the measurement will be saved without mapping',
  );
  String get shareOnMapSwitch =>
      _t('ارسم النتيجة على الخريطة', 'Plot result on the map');
  String get shareOnMapSubtitle => _t(
    'يُحفظ القياس مع نوع الشبكة (واي فاي أو خلوي) في خلية تقريبية نحو 1 كم',
    'Saves the measurement with connection type (Wi‑Fi or cellular) in an approximate ~1 km cell',
  );
  String get cancelTest => _t('إلغاء الاختبار', 'Cancel test');
  String get startSpeedTest => _t('ابدأ فحص السرعة', 'Start speed test');
  String get newTest => _t('اختبار جديد', 'New test');
  String get startAction => _t('ابدأ', 'Start');
  String get jitterDisclaimer => _t(
    'Jitter وفقد الحزم غير متاحين؛ HTTP لا يقيس فقد حزم الشبكة. شركة الاتصالات غير معروفة دون مصدر موثوق.',
    'Jitter and packet loss are unavailable; HTTP cannot measure packet loss. The carrier is unknown without a trusted source.',
  );
  String get yourResultTitle => _t('نتيجتك الفعلية', 'Your actual result');
  String get connectionMobileNetwork => _t('شبكة الجوال', 'Mobile network');
  String get connectionUncertain =>
      _t('نوع الاتصال غير مؤكد', 'Connection type uncertain');
  String get noLocationForTest => _t(
    'لم يُجمع موقع لهذا الاختبار؛ أوقف المساهمة لحفظ نتيجة خاصة.',
    'No location was collected for this test; turn off sharing to save a private result.',
  );
  String get savedToDatabase =>
      _t('تم الحفظ في قاعدة البيانات', 'Saved to the database');
  String get saveResultShare =>
      _t('حفظ النتيجة والمساهمة بالخريطة', 'Save result and contribute to the map');
  String get saveResultPrivate =>
      _t('حفظ نتيجة خاصة على الخادم', 'Save private result on the server');
  String mappedCellLine(String id) => _t(
    'رُسم على الخريطة — خلية $id (طبقة قياساتك بالأحمر)',
    'Plotted on the map — cell $id (your measurements layer in red)',
  );
  String get aiAnalysisTitle =>
      _t('تحليل الذكاء الاصطناعي', 'AI analysis');
  String get aiNoResult => _t('لا توجد نتيجة', 'No result');
  String aiAnalysisFailed(String error) => _t(
    'تعذر التحليل الذكي: $error\n(تأكد أن المدير حفظ مفتاح Gemini في لوحة الإدارة)',
    'Smart analysis failed: $error\n(Make sure the admin saved a Gemini key in the admin panel)',
  );
  String get mapLayerNote => _t(
    'قياساتك تظهر فورًا في طبقة «قياساتك» على الخريطة. الطبقة العامة تحتاج عينات من عدة مساهمين.',
    'Your measurements appear immediately on the “Your measurements” map layer. The public layer needs samples from multiple contributors.',
  );
  String get realHistoryTitle =>
      _t('سجل القياسات الفعلية', 'Live measurement history');
  String get realHistorySubtitle => _t(
    'من قاعدة البيانات • نتائج مكتملة فقط',
    'From the database • completed results only',
  );
  String get signInToViewHistory =>
      _t('تسجيل الدخول لاستعراض سجلي', 'Sign in to view my history');
  String get realHistoryEmpty => _t(
    'لا قياسات حقيقية بعد. نتائج المحاكاة القديمة غير مدرجة.',
    'No live measurements yet. Older simulated results are not listed.',
  );
  String get httpTestCompleted =>
      _t('قياس نقل HTTP مكتمل', 'HTTP transfer test completed');
  String get loadMore => _t('تحميل المزيد', 'Load more');
  String get deleteMyMeasurementsFromServer =>
      _t('حذف قياساتي من الخادم', 'Delete my measurements from the server');
  String get deleteAllMeasurementsTitle =>
      _t('حذف جميع قياساتك؟', 'Delete all your measurements?');
  String get deleteAllMeasurementsBody => _t(
    'سيُحذف سجلك ومساهماتك من الخريطة نهائيًا من الخادم.',
    'Your history and map contributions will be permanently deleted from the server.',
  );
  String get deleteMyMeasurements =>
      _t('حذف قياساتي', 'Delete my measurements');

  // Speed phases / location errors
  String get locationServiceDisabled => _t(
    'خدمة الموقع متوقفة؛ يمكنك الاختبار دون مشاركة الموقع',
    'Location services are off; you can still test without sharing location',
  );
  String get locationPermissionDenied => _t(
    'لم يُمنح إذن الموقع. لن يُرسل موقع؛ يمكنك إجراء اختبار خاص',
    'Location permission denied. No location will be sent; you can run a private test',
  );
  String get locationUnavailable => _t(
    'تعذر تحديد الموقع؛ فعّل GPS وانتظر إشارة ثم أعد المحاولة، أو أوقف مشاركة الموقع',
    'Could not determine location; enable GPS, wait for a signal, then retry — or turn off location sharing',
  );
  String locationAccuracyPoor(int meters) => _t(
    'دقة الموقع ضعيفة (~$meters م). اخرج لمكان مفتوح أو فعّل GPS الدقيق ثم أعد المحاولة',
    'Location accuracy is weak (~$meters m). Move outdoors or enable precise GPS, then try again',
  );
  String get signInBeforeTest =>
      _t('سجّل الدخول بالخادم قبل إجراء الاختبار', 'Sign in to the server before running a test');
  String get testCancelledBeforeTransfer =>
      _t('أُلغي الاختبار قبل نقل البيانات', 'Test cancelled before data transfer');
  String get measurementServerUndefined =>
      _t('خادم القياس غير معرّف', 'Measurement server is not configured');
  String get phaseVerifyPath =>
      _t('التحقق من مسار القياس', 'Verifying measurement path');
  String get phaseHttpLatency =>
      _t('قياس زمن الاستجابة HTTP', 'Measuring HTTP latency');
  String get phaseDownload =>
      _t('قياس التنزيل بنقل بيانات فعلية', 'Measuring download with real data transfer');
  String get phaseUpload =>
      _t('قياس الرفع بنقل بيانات فعلية', 'Measuring upload with real data transfer');
  String get testIncompleteCancelled => _t(
    'أُلغي الاختبار أو انتهت مدته؛ لا توجد نتيجة مكتملة',
    'Test cancelled or timed out; no complete result',
  );
  String get transferTooSmall => _t(
    'حجم النقل أقل من الحد الأدنى المقبول',
    'Transfer size is below the accepted minimum',
  );
  String get latencyMeasureFailed =>
      _t('تعذر قياس زمن الاستجابة', 'Could not measure latency');
  String get phaseComplete => _t('اكتمل القياس', 'Measurement complete');
  String get measurementServerTimeout => _t(
    'انتهت مهلة الاتصال بخادم القياس',
    'Timed out connecting to the measurement server',
  );
  String get measurementServerDisconnected => _t(
    'انقطع الاتصال بخادم القياس أثناء النقل',
    'Lost connection to the measurement server during transfer',
  );
  String get testInterrupted => _t(
    'انقطع الاختبار؛ لم تُنشأ أو تُحفظ نتيجة مكتملة',
    'Test interrupted; no complete result was created or saved',
  );
  String get testCancelled => _t('تم إلغاء الاختبار', 'Test cancelled');
  String get compressedTransferRejected => _t(
    'رفض نتيجة نقل مضغوط؛ أعد المحاولة',
    'Compressed transfer result rejected; try again',
  );
  String get transferRejected => _t(
    'رفض خادم القياس النقل أو انتهت ميزانيته',
    'Measurement server rejected the transfer or exhausted its budget',
  );
  String get downloadIncomplete =>
      _t('تنزيل ناقص؛ لن تُقبل النتيجة', 'Incomplete download; result will not be accepted');

  // API errors
  String get apiHttpsRequired => _t(
    'عنوان الخدمة يحتاج HTTPS؛ HTTP مسموح فقط للتطوير على الجهاز نفسه',
    'The service URL must use HTTPS; HTTP is allowed only for local development',
  );
  String get apiRequestRejected => _t(
    'رفض الخادم الطلب؛ تحقق من الحقول والاتصال',
    'The server rejected the request; check the fields and your connection',
  );
  String get apiTimeout => _t(
    'انتهت مهلة الخدمة؛ خادم Render قد يكون في إقلاع أول، أعد المحاولة خلال ثوانٍ',
    'Service timed out; the Render server may be cold-starting — retry in a few seconds',
  );
  String get apiConnectionFailed => _t(
    'تعذر الاتصال بخدمة الشبكة. تحقق من اتصالك وإعداد عنوان API',
    'Could not reach the network service. Check your connection and API URL',
  );
  String get cellularDataUnavailable => _t(
    'بيانات الجوال غير متاحة. فعّل شبكة الجوال ثم أعد المحاولة',
    'Mobile data is unavailable. Enable cellular data and try again',
  );

  // ── Map ──────────────────────────────────────────────────────
  String get internetQualityMapTitle =>
      _t('خريطة جودة الإنترنت', 'Internet quality map');
  String get goToMyLocationTitle =>
      _t('العودة إلى موقعي', 'Go to my location');
  String get goToMyLocationBody => _t(
    'سيُستخدم إذن الموقع لتحريك الخريطة إلى موقعك الحالي. العرض الافتراضي يبقى حائل.',
    'Location permission will be used to pan the map to your current position. The default view remains Hail.',
  );
  String get locationUnavailableSnack => _t(
    'الموقع غير متاح أو لم يُمنح الإذن',
    'Location unavailable or permission denied',
  );
  String get mapDataTitle => _t('بيانات الخريطة', 'Map data');
  String get cellSummaryTitle =>
      _t('ملخص الخلية الجغرافية', 'Geographic cell summary');
  String get mapNoDataMessage => _t(
    'لا بيانات منشورة كافية في هذه المنطقة بعد.',
    'Not enough published data in this area yet.',
  );
  String mapCellsAvailable(int n) => _t(
    '$n خلية متاحة؛ اضغط منطقة ملونة لاستعراض مؤشرات منفصلة.',
    '$n cells available; tap a colored area to inspect metrics.',
  );
  String get mapNoServerData =>
      _t('لم تصل بيانات من الخادم', 'No data received from the server');
  String mapLastUpdate(String time) =>
      _t('آخر تحديث: $time', 'Last update: $time');
  String get mapGrayCellsNote => _t(
    'الرمادي: عينة غير كافية أو بيانات قديمة. تُخفى الخلايا التي يقل عدد مساهميها عن الحد المسموح.',
    'Gray: insufficient sample or stale data. Cells below the contributor threshold are hidden.',
  );
  String cellIdLine(String id) => _t('خلية $id', 'Cell $id');
  String get cellStatusReady => _t('جاهزة للتقييم', 'Ready for scoring');
  String get cellStatusStale => _t('بيانات قديمة', 'Stale data');
  String get cellStatusInsufficient => _t(
    'بيانات غير كافية؛ لا يصدر حكم على جودة المنطقة',
    'Insufficient data; no quality judgment for this area',
  );
  String get cellValidSamples => _t('العينات الصالحة', 'Valid samples');
  String get cellAgeHours => _t('عمر أحدث قياس', 'Age of latest measurement');
  String get cellLastMeasurement => _t('آخر قياس', 'Last measurement');
  String get cellTechnicalDisclaimer => _t(
    'Jitter وفقد الحزم غير متاحين عبر HTTP. لا تُعرض هوية المساهمين ولا إحداثيات دقيقة.',
    'Jitter and packet loss are unavailable over HTTP. Contributor identities and precise coordinates are not shown.',
  );
  String get cellAnalysisPeriod => _t('فترة التحليل', 'Analysis period');
  String get mapColorsDisclaimer => _t(
    'الألوان تعكس المؤشر المحدد في الفلاتر فقط.',
    'Colors reflect only the metric selected in the filters.',
  );
  String get mapLegendTitle => _t('دليل الخريطة', 'Map legend');
  String get legendDensity => _t(
    'الأرجواني الأغمق = كثافة قياسات أعلى',
    'Darker purple = higher measurement density',
  );
  String get qualityGood => _t('جيدة', 'Good');
  String get qualityModerate => _t('متوسطة', 'Moderate');
  String get qualityPoor => _t('ضعيفة', 'Poor');
  String get qualityVeryPoor => _t('ضعيفة جدًا', 'Very poor');
  String get qualityInsufficient =>
      _t('عينة غير كافية أو بيانات قديمة', 'Insufficient sample or stale data');
  String get dataFiltersTitle => _t('فلاتر البيانات', 'Data filters');
  String get viewAreaLabel => _t('اختيار منطقة العرض', 'View area');
  String get viewCityHail => _t('حائل • عرض المدينة', 'Hail • city view');
  String get filterLast24h => _t('آخر 24 ساعة', 'Last 24 hours');
  String filterLastDays(int d) => _t('آخر $d يومًا', 'Last $d days');
  String get customDateRange => _t('نطاق تاريخ مخصص', 'Custom date range');
  String get displayMetric => _t('المؤشر المعروض', 'Displayed metric');
  String get metricDownloadQuality => _t('جودة التنزيل', 'Download quality');
  String get metricUploadQuality => _t('جودة الرفع', 'Upload quality');
  String get metricHttpQuality =>
      _t('جودة الاستجابة HTTP', 'HTTP latency quality');
  String get metricDensityOnly =>
      _t('كثافة القياسات فقط', 'Measurement density only');
  String get connectionType => _t('نوع الاتصال', 'Connection type');
  String get allConnections => _t('جميع الاتصالات', 'All connections');
  String get minSamplesLabel => _t('الحد الأدنى للعينات', 'Minimum samples');
  String get applyFilters => _t('تطبيق الفلاتر', 'Apply filters');
  String get resetFilters => _t('إعادة ضبط الفلاتر', 'Reset filters');
  String get compareCellsTitle => _t('مقارنة الخلايا', 'Compare cells');
  String get compareCellsSubtitle => _t(
    'نفس الفترة والفلاتر • ترتيب حسب وسيط التنزيل',
    'Same period and filters • sorted by median download',
  );
  String get compareCellsInsufficient => _t(
    'لا توجد خليتان حديثتان كافيتان للمقارنة.',
    'Not enough recent cells to compare.',
  );
  String sampleCount(int count) => _t('$count عينة', '$count samples');
  String get zoomIn => _t('تكبير', 'Zoom in');
  String get zoomOut => _t('تصغير', 'Zoom out');
  String get backToHail => _t('العودة لحائل', 'Back to Hail');
  String get myCurrentLocation => _t('موقعي الحالي', 'My current location');
  String get toggleMapTheme =>
      _t('تبديل مظهر الخريطة', 'Toggle map appearance');
  String get toggleHeatmap =>
      _t('إظهار أو إخفاء الحرارة', 'Show or hide heatmap');
  String get fullScreen => _t('ملء الشاشة', 'Full screen');
  String get tooltipFilters => _t('فلاتر البيانات', 'Data filters');
  String get tooltipRefresh => _t('تحديث البيانات', 'Refresh data');
  String get tooltipSpeedTest => _t('اختبار الإنترنت', 'Internet test');
  String get tooltipCompare => _t('مقارنة المناطق', 'Compare areas');
  String get tooltipLegend => _t('دليل الألوان', 'Color legend');
  String get mapBannerError =>
      _t('تعذر تحميل بيانات الخريطة', 'Could not load map data');
  String mapBannerMine(int mine, int published) => published == 0
      ? _t(
          '$mine قياس لك على الخريطة',
          '$mine of your measurements on the map',
        )
      : _t(
          '$mine قياس لك على الخريطة • $published خلية منشورة',
          '$mine of your measurements • $published published cells',
        );
  String mapBannerPublic(int n) =>
      _t('$n خلية مجمّعة', '$n aggregated cells');
  String get mapBannerEmpty =>
      _t('لا خلايا في هذه المنطقة بعد', 'No cells in this area yet');
  String get heatmapHidden => _t('الحرارة مخفية', 'Heatmap hidden');
  String get mapTilesFailed =>
      _t('تعذر تحميل بعض أجزاء الخريطة', 'Some map tiles failed to load');
  String get mapAttribution => '© OpenStreetMap © CARTO';
  String get mapQualityGuidelinesFallback => _t(
    'حدود إرشادية للمشروع، وليست معيارًا رسميًا.',
    'Project guidance thresholds, not an official standard.',
  );
  String mapLegendMinSamplesNote(int min) => _t(
    'الحد الأدنى: $min قياسات و3 مساهمين مختلفين على الأقل. الأسماء الإدارية غير مستنتجة من الخلايا.',
    'Minimum: $min measurements and at least 3 distinct contributors. Administrative names are not inferred from cells.',
  );
  String get cellSamplesWithheld => _t(
    'غير منشور لحماية الخصوصية',
    'Not published to protect privacy',
  );
  String cellValidSamplesLine(String count) => _t(
    'العينات الصالحة: $count',
    'Valid samples: $count',
  );
  String cellAgeHoursValue(int hours) => _t(
    'عمر أحدث قياس: $hours ساعة',
    'Age of latest measurement: $hours hours',
  );
  String cellLastMeasurementValue(String time) => _t(
    'آخر قياس: $time',
    'Last measurement: $time',
  );
  String cellAnalysisPeriodRange(String start, String end) => _t(
    'فترة التحليل: $start — $end',
    'Analysis period: $start — $end',
  );
  String cellMetricRow(String label, String mean, String median, String unit) =>
      _t(
        '$label: المتوسط $mean • الوسيط $median $unit',
        '$label: mean $mean • median $median $unit',
      );
  String filterMinDownloadAtLeast(int mbps) => _t(
    'تنزيل لا يقل عن $mbps Mbps',
    'Download at least $mbps Mbps',
  );
  String get filterPingNoExtraCap => _t(
    'الاستجابة: دون حد إضافي',
    'Latency: no extra cap',
  );
  String filterPingAtMost(int ms) =>
      _t('الاستجابة لا تتجاوز $ms ms', 'Latency at most $ms ms');
  String get mapCarrierFilterUnavailable => _t(
    'شركة الاتصالات غير متاحة من مصدر موثوق؛ فلترها غير مفعّل.',
    'Carrier is unavailable from a trusted source; that filter is disabled.',
  );
  String compareCellMetrics(String down, String up, String ping) => _t(
    'تنزيل $down Mbps • رفع $up Mbps • HTTP $ping ms',
    'Download $down Mbps • upload $up Mbps • HTTP $ping ms',
  );
  String mapBannerFilterSummary(String metric, int samples, String connection) =>
      _t(
        '$metric • $samples+ عينات • $connection',
        '$metric • $samples+ samples • $connection',
      );
  String mapBannerUpdated(String time, int days) => _t(
    'تحديث $time • $days يوم',
    'Updated $time • $days days',
  );
  String mapBannerThresholds(double minDown, num maxPing) => _t(
    'تنزيل ≥ $minDown Mbps • استجابة ≤ $maxPing ms',
    'Download ≥ $minDown Mbps • latency ≤ $maxPing ms',
  );
  String get unpublishedPrivacyNote => _t(
    'تحديث الخريطة العامة يتطلب الحد الأدنى للعينات ومساهمين متعددين؛ مساهمة واحدة تظهر في طبقة قياساتك.',
    'The public map needs a minimum sample size and multiple contributors; a single contribution appears on your personal layer.',
  );

  // ── Reports ──────────────────────────────────────────────────
  String get reportsLocalNotStc => _t(
    'محفوظة على هذا الجهاز • لم تُرسل إلى STC',
    'Saved on this device • not sent to STC',
  );
  String get createNewReport => _t('إنشاء بلاغ جديد', 'Create new report');
  String get filterAll => _t('الكل', 'All');
  String get filterOpen => _t('مفتوحة', 'Open');
  String get filterClosed => _t('مغلقة', 'Closed');
  String get reportsEmptyTitle => _t('لا توجد بلاغات هنا', 'No reports here');
  String get reportsEmptyBody => _t(
    'أضف بلاغًا أو جرّب اختيار حالة أخرى.',
    'Add a report or try a different status filter.',
  );
  String get notSentToStc => _t('لم يُرسل إلى STC', 'Not sent to STC');
  String get diagnoseFirst =>
      _t('ابدأ بتشخيص المشكلة أولًا', 'Start by diagnosing the issue first');
  String get newReport => _t('بلاغ جديد', 'New report');
  String get newReportIntro => _t(
    'صف المشكلة، وخلّنا نتابعها',
    'Describe the issue and we will track it',
  );
  String get issueType => _t('نوع المشكلة', 'Issue type');
  String get reportCategorySlowInternet =>
      _t('بطء الإنترنت', 'Slow internet');
  String get reportCategoryWeakSignal =>
      _t('ضعف الإشارة', 'Weak signal');
  String get reportCategoryDroppedCalls =>
      _t('انقطاع المكالمات', 'Dropped calls');
  String get reportCategoryUnstable =>
      _t('اتصال غير مستقر', 'Unstable connection');
  String get neighborhood => _t('الحي', 'Neighborhood');
  String get problemDescription => _t('وصف المشكلة', 'Problem description');
  String get problemDescriptionHint => _t(
    'متى بدأت المشكلة؟ وهل تحدث داخل المنزل أو خارجه؟',
    'When did the problem start? Indoors or outdoors?',
  );
  String get descriptionMinLength => _t(
    'اكتب وصفًا من 10 أحرف على الأقل',
    'Enter a description of at least 10 characters',
  );
  String get saveReportLocally =>
      _t('حفظ البلاغ على الجهاز', 'Save report on device');
  String get reportLocalOnlyNote => _t(
    'لن يُرسل البلاغ إلى مزود الخدمة؛ يُحفظ محليًا للمتابعة التجريبية.',
    'The report will not be sent to the carrier; it is saved locally for demo follow-up.',
  );
  String get reportDetails => _t('تفاصيل البلاغ', 'Report details');
  String reportAreaLine(String area) => _t('الحي: $area', 'Neighborhood: $area');
  String reportCreatedLine(String date) =>
      _t('تاريخ الإنشاء: $date', 'Created: $date');
  String get followUpPath => _t('مسار المتابعة', 'Follow-up path');
  String get stepReportCreated => _t('إنشاء البلاغ', 'Report created');
  String get stepAddedLocally =>
      _t('أُضيف على هذا الجهاز', 'Added on this device');
  String get stepLocalSave => _t('الحفظ المحلي', 'Local save');
  String get stepSaveFailed => _t('تعذر الحفظ الدائم', 'Persistent save failed');
  String get stepAutoSaveOn =>
      _t('الحفظ التلقائي مفعّل', 'Auto-save enabled');
  String get stepManualSave =>
      _t('استخدم الحفظ اليدوي', 'Use manual save');
  String get stepSupportLink => _t('الربط بالدعم', 'Support integration');
  String get stepNotLinkedStc => _t(
    'غير متصل • لم يُرسل البلاغ إلى STC',
    'Offline • report not sent to STC',
  );
  String get stepLocalStatus =>
      _t('حالة المتابعة المحلية', 'Local follow-up status');
  String get reportStatusPending =>
      _t('بانتظار الربط', 'Pending linkage');
  String get reportStatusClosedDemo =>
      _t('مغلق تجريبيًا', 'Closed (demo)');
  String get initialRecommendation =>
      _t('التوصية الأولية', 'Initial recommendation');
  String get recommendationDisclaimer => _t(
    'توصية توضيحية بقواعد محلية وليست تشخيصًا مؤكدًا.',
    'Illustrative recommendation from local rules — not a confirmed diagnosis.',
  );
  String get reopenLocally => _t('إعادة فتح محليًا', 'Reopen locally');
  String get closeLocally => _t('إغلاق البلاغ محليًا', 'Close report locally');
  String get copyReportSummary =>
      _t('نسخ ملخص البلاغ', 'Copy report summary');
  String get reportCopiedToast =>
      _t('تم نسخ ملخص البلاغ', 'Report summary copied');
  String get clipboardReportFooter => _t(
    'بلاغ تجريبي محلي، لم يُرسل إلى STC',
    'Local demo report, not sent to STC',
  );
  String get noticeReportSavedTitle =>
      _t('تم حفظ بلاغك', 'Your report was saved');
  String get noticeReportSavedBody => _t(
    'البلاغ محفوظ على جهازك بانتظار الربط بخدمة الدعم.',
    'The report is saved on your device pending support integration.',
  );
  String get noticeDemoTestTitle =>
      _t('اكتمل الاختبار التجريبي', 'Demo test completed');
  String get noticeDemoTestBody => _t(
    'أضفنا النتيجة إلى سجل القياسات.',
    'We added the result to the measurement log.',
  );
  String get noticeStatusUpdateTitle =>
      _t('تحديث حالة البلاغ', 'Report status update');
  String noticeStatusUpdateBody(String status) =>
      _t('حالة البلاغ المحلية: $status', 'Local report status: $status');

  // ── Notifications / sync ─────────────────────────────────────
  String get markAllRead => _t('قراءة الكل', 'Mark all as read');
  String get notificationsDisabled => _t(
    'الإشعارات الجديدة متوقفة من الإعدادات.',
    'New notifications are disabled in Settings.',
  );
  String get noticesEmptyTitle => _t('كل شيء هادئ هنا', 'All quiet here');
  String get noticesEmptyBody => _t(
    'ستظهر تحديثات البلاغات ونتائج الاختبارات هنا.',
    'Report updates and test results will appear here.',
  );
  String get syncHeroTitle =>
      _t('بياناتك معك على جهازك', 'Your data stays on your device');
  String get syncOfflineBlurb => _t(
    'يمكن إنشاء البلاغات واستعراض السجل دون اتصال بعد تحميل التطبيق. الخريطة تحتاج الإنترنت لتحميل الطرق.',
    'You can create reports and browse history offline after loading the app. The map needs internet to load roads.',
  );
  String get storageFailed =>
      _t('تعذر الحفظ على الجهاز', 'Could not save on device');
  String get storageAvailable =>
      _t('التخزين المحلي متاح', 'Local storage available');
  String get noSaveYet => _t('لم تُحفظ تغييرات بعد', 'No changes saved yet');
  String lastSavedLine(String date) =>
      _t('آخر حفظ: $date', 'Last saved: $date');
  String get syncDataSplitNote => _t(
    'البلاغات: محلية • قياسات الشبكة: عبر خدمة API المستقلة',
    'Reports: local • network measurements: via the independent API service',
  );
  String get reportsSentToStcCount =>
      _t('البلاغات المرسلة إلى STC: 0', 'Reports sent to STC: 0');
  String localItemsCount(int n) =>
      _t('عناصر محلية: $n', 'Local items: $n');
  String get saveDataNow => _t('حفظ البيانات الآن', 'Save data now');
  String get saveFailedToast => _t(
    'تعذر الحفظ؛ تحقق من إتاحة تخزين المتصفح',
    'Save failed; check that browser/device storage is available',
  );
  String get saveSuccessToast =>
      _t('تم حفظ البيانات على هذا الجهاز', 'Data saved on this device');
  String get syncLongDisclaimer => _t(
    'لا تُزامن البلاغات المحلية مع STC في هذه النسخة. قياسات الشبكة المكتملة تُحفظ على خادم SmartCare عند موافقتك.',
    'Local reports are not synced to STC in this build. Completed network measurements are saved to the SmartCare server when you consent.',
  );

  // ── Admin ────────────────────────────────────────────────────
  String get adminSignInRequired =>
      _t('سجّل الدخول بحساب المدير أولًا', 'Sign in with the admin account first');
  String get adminAccessRequiredTitle =>
      _t('دخول المدير مطلوب', 'Admin access required');
  String get adminAccessRequiredBody => _t(
    'سجّل الدخول برقم 0552515874 وكلمة المرور الخاصة بالمدير لفتح اللوحة الكاملة.',
    'Sign in with 0552515874 and the admin password to open the full panel.',
  );
  String get adminSignIn => _t('تسجيل دخول المدير', 'Admin sign-in');
  String get tabOverview => _t('نظرة عامة', 'Overview');
  String get tabUsers => _t('المستخدمون', 'Users');
  String get tabMeasurements => _t('القياسات', 'Measurements');
  String get tabAiSettings => _t('الذكاء والضبط', 'AI & settings');
  String adminWelcome(String name) => _t('مرحبًا، $name', 'Hello, $name');
  String get adminDefaultName => _t('المدير', 'Admin');
  String get adminFullPermissions =>
      _t('صلاحيات كاملة على الخادم', 'Full server permissions');
  String get metricUsers => _t('المستخدمون', 'Users');
  String get metricAdmins => _t('المدراء', 'Admins');
  String get metricMeasurements => _t('القياسات', 'Measurements');
  String get metricOnMap => _t('على الخريطة', 'On map');
  String get metricAvgDownload =>
      _t('متوسط التحميل Mbps', 'Avg download Mbps');
  String get metricAvgUpload => _t('متوسط الرفع Mbps', 'Avg upload Mbps');
  String get metricAvgPing => _t('متوسط البنق ms', 'Avg ping ms');
  String get serverStatus => _t('حالة الخادم', 'Server status');
  String get byConnectionType =>
      _t('حسب نوع الاتصال', 'By connection type');
  String get topActiveUsers =>
      _t('أكثر المستخدمين نشاطًا', 'Most active users');
  String get userSearchHint =>
      _t('بحث بالاسم أو الرقم…', 'Search by name or number…');
  String userCountLine(int n, int total) =>
      _t('$n من $total مستخدم', '$n of $total users');
  String get deleteUser => _t('حذف المستخدم', 'Delete user');
  String get deleteUserConfirmTitle =>
      _t('حذف المستخدم؟', 'Delete user?');
  String deleteUserConfirmBody(String phone) => _t(
    'سيتم حذف $phone وكل قياساته نهائيًا.',
    '$phone and all of their measurements will be permanently deleted.',
  );
  String get userDeletedToast =>
      _t('تم حذف المستخدم', 'User deleted');
  String recentMeasurementsHeader(int n) =>
      _t('آخر $n قياس على الخادم', 'Last $n measurements on the server');
  String get measurementsEmptyTitle =>
      _t('لا قياسات بعد', 'No measurements yet');
  String get measurementsEmptyBody => _t(
    'ستظهر هنا فور حفظ أول فحص سرعة.',
    'They will appear here after the first saved speed test.',
  );
  String get deleteMeasurement => _t('حذف القياس', 'Delete measurement');
  String get measurementDeletedToast =>
      _t('تم حذف القياس', 'Measurement deleted');
  String get geminiServerKeyTitle =>
      _t('مفتاح Gemini للخادم بالكامل', 'Server-wide Gemini key');
  String get geminiServerKeyBlurb => _t(
    'يُحفظ مرة واحدة في قاعدة البيانات ويُستخدم للويب والتطبيق معًا.',
    'Saved once in the database and used for both web and the app.',
  );
  String get geminiNoKeyYet =>
      _t('لا يوجد مفتاح محفوظ بعد', 'No key saved yet');
  String geminiKeyMasked(String masked) =>
      _t('المفتاح المحفوظ: $masked', 'Saved key: $masked');
  String get geminiApiKeyLabel =>
      _t('مفتاح Gemini API', 'Gemini API key');
  String get geminiApiKeyHint => _t(
    'الصق المفتاح هنا ثم احفظ مرة واحدة',
    'Paste the key here and save once',
  );
  String get saveToDatabase =>
      _t('حفظ في قاعدة البيانات', 'Save to database');
  String get geminiSavedToast =>
      _t('تم حفظ إعدادات Gemini', 'Gemini settings saved');
  String get tryAnalysis => _t('تجربة التحليل', 'Try analysis');
  String get analyzeInputHint => _t(
    'اكتب وصف مشكلة شبكة أو ألصق ملخص قياسات…',
    'Describe a network issue or paste a measurement summary…',
  );
  String get loginDetails => _t('بيانات الدخول', 'Sign-in details');
  String get adminPhoneLine =>
      _t('رقم المدير: 0552515874', 'Admin phone: 0552515874');
  String get geminiKeyPersistNote => _t(
    'بعد الحفظ لا تحتاج إعادة إدخال المفتاح إلا إذا أردت تغييره.',
    'After saving you do not need to re-enter the key unless you want to change it.',
  );
  String get databaseLabel => _t('قاعدة البيانات', 'Database');

  // ── AI / help / privacy / about ──────────────────────────────
  String get aiSignInRequired =>
      _t('سجّل الدخول لاستخدام التحليل الذكي', 'Sign in to use smart analysis');
  String get aiAssistIntro => _t(
    'يستخدم مفتاح Gemini الذي حفظه المدير مرة واحدة في قاعدة بيانات الخادم — مشترك للويب والتطبيق.',
    'Uses the Gemini key the admin saved once in the server database — shared by web and app.',
  );
  String get aiInputHint => _t(
    'صف مشكلة الشبكة أو الصق ملخص قياس…',
    'Describe the network issue or paste a measurement summary…',
  );
  String get helpTitle => _t('نحن هنا لمساعدتك', 'We’re here to help');
  String get faqAddReportQ =>
      _t('كيف أضيف بلاغًا؟', 'How do I add a report?');
  String get faqAddReportA => _t(
    'من بلاغاتي اختر إنشاء بلاغ جديد، أو ابدأ بتشخيص المشكلة عبر المساعد ثم احفظ النتيجة.',
    'From My reports choose Create new report, or diagnose with the assistant then save.',
  );
  String get faqRealMeasurementsQ =>
      _t('هل القياسات حقيقية؟', 'Are measurements real?');
  String get faqRealMeasurementsA => _t(
    'نعم. فحص السرعة ينقل بيانات فعلية عبر خادم SmartCare ويحفظ النتائج بعد موافقتك.',
    'Yes. The speed test transfers real data via the SmartCare server and saves results after you consent.',
  );
  String get faqStcReportsQ =>
      _t('هل يصل البلاغ إلى STC؟', 'Does the report reach STC?');
  String get faqStcReportsA => _t(
    'لا، البلاغات محفوظة على جهازك فقط. الربط بمزود الخدمة يحتاج خدمة خلفية وصلاحيات مناسبة.',
    'No. Reports stay on your device only. Carrier integration needs a backend service and proper permissions.',
  );
  String get faqOfflineQ => _t(
    'ماذا يحدث عند انقطاع الإنترنت؟',
    'What happens when the internet goes out?',
  );
  String get faqOfflineA => _t(
    'بعد تحميل التطبيق، يمكن استخدام الواجهات وحفظ البلاغات محليًا. تحميل أجزاء جديدة من الخريطة يتطلب اتصالًا.',
    'After loading the app, you can use the UI and save reports locally. Loading new map tiles requires a connection.',
  );
  String get faqAccountSafeQ =>
      _t('هل الحساب آمن للإنتاج؟', 'Is the account production-safe?');
  String get faqAccountSafeA => _t(
    'الدخول يستخدم حسابًا وكلمة مرور على خادم SmartCare. ملكية رقم الجوال غير متحققة برسائل SMS، ولا يرتبط الحساب بشركة STC.',
    'Sign-in uses an account and password on the SmartCare server. Phone ownership is not SMS-verified, and the account is not linked to STC.',
  );
  String get aboutProductTitle => 'STC SmartCare AI';
  String get aboutBlurb => _t(
    'مشروع تصوري لتجربة رعاية الشبكة في حائل مع قياس حقيقي وخريطة جودة.',
    'A concept experience for network care in Hail with live measurement and a quality map.',
  );
  String get aboutVersion => _t(
    'الإصدار 1.0 • نموذج واجهات تفاعلي',
    'Version 1.0 • interactive UI concept',
  );
  String get privacyHero => _t(
    'أنت تعرف أين تُحفظ بياناتك',
    'You know where your data is stored',
  );
  String get privacyLocalStorage => _t(
    'يحفظ هذا النموذج الاسم ورقم الجوال التجريبي والبلاغات والقياسات والإعدادات في التخزين المحلي للتطبيق أو المتصفح. هذا التخزين غير مشفر ولا يمثل حسابًا سحابيًا.',
    'This build stores the name, demo phone number, reports, measurements and settings in the app or browser local storage. It is not encrypted and is not a cloud account.',
  );
  String get privacyLocationMaps => _t(
    'لا يُطلب الموقع إلا بموافقتك لتحريك الخريطة أو مشاركة خلية تقريبية. يمكن الاختبار دون مشاركة الموقع. تُحمّل صور الطرق من مزود الخرائط؛ يتلقى طلبات أجزاء الخريطة وعنوان الإنترنت، ولا يتلقى رقم حسابك من التطبيق.',
    'Location is requested only with your consent to pan the map or share an approximate cell. You can test without sharing location. Map tiles come from the map provider, which receives tile requests and your IP — not your account number from the app.',
  );
  String get privacyReportsMeasurements => _t(
    'البلاغات لا تُرسل إلى STC. القياسات المكتملة التي توافق على حفظها تُرسل إلى خادم SmartCare. الموقع اختياري، ويُقرب إلى خلية بنحو 1 كم قبل الإرسال. لا تُخزّن إحداثيات GPS الدقيقة ولا تُنشر هويات المساهمين. تُحتفظ القياسات 90 يومًا وتُحذف من شاشة السجل. جلسة الدخول محفوظة حتى تسجيل الخروج. مسح بيانات المتصفح/التطبيق ينهي الجلسة المحلية فقط ولا يحذف قياسات الخادم.',
    'Reports are not sent to STC. Completed measurements you agree to save are sent to the SmartCare server. Location is optional and rounded to an ~1 km cell before upload. Exact GPS coordinates are not stored and contributor identities are not published. Measurements are kept for 90 days and can be deleted from history. Your session lasts until you sign out. Clearing browser/app data ends the local session only and does not delete server measurements.',
  );

  // AI prompt (sent to server — keep bilingual clarity)
  String aiSpeedPrompt({
    required String download,
    required String upload,
    required String ping,
    required String connection,
    String? cellId,
  }) {
    if (isArabic) {
      final cell = cellId != null
          ? '- رُسم على خلية: $cellId'
          : '- لم تُشارك إحداثيات على الخريطة';
      return 'حلّل نتيجة فحص سرعة شبكة للمستخدم:\n'
          '- التحميل: $download Mbps\n'
          '- الرفع: $upload Mbps\n'
          '- البنق: $ping ms\n'
          '- نوع الاتصال: $connection\n'
          '$cell\n'
          'اذكر تقييمًا مختصرًا وجودة الاستخدام اليومي ونصيحة واحدة عملية.';
    }
    final cell = cellId != null
        ? '- Mapped to cell: $cellId'
        : '- Location was not shared on the map';
    return 'Analyze this network speed test result:\n'
        '- Download: $download Mbps\n'
        '- Upload: $upload Mbps\n'
        '- Ping: $ping ms\n'
        '- Connection: $connection\n'
        '$cell\n'
        'Give a brief rating, everyday-use quality, and one practical tip.';
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'ar' || locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
