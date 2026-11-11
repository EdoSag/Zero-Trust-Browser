// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppL10nHe extends AppL10n {
  AppL10nHe([String locale = 'he']) : super(locale);

  @override
  String get cancel => 'ביטול';

  @override
  String get save => 'שמירה';

  @override
  String get delete => 'מחיקה';

  @override
  String get clear => 'ניקוי';

  @override
  String get open => 'פתיחה';

  @override
  String get share => 'שיתוף';

  @override
  String get edit => 'עריכה';

  @override
  String get remove => 'הסרה';

  @override
  String get undo => 'ביטול הפעולה';

  @override
  String get allow => 'אישור';

  @override
  String get block => 'חסימה';

  @override
  String get copied => 'הועתק';

  @override
  String get more => 'עוד';

  @override
  String get close => 'סגירה';

  @override
  String get reload => 'טעינה מחדש';

  @override
  String get back => 'חזרה';

  @override
  String get forward => 'קדימה';

  @override
  String get home => 'דף הבית';

  @override
  String get menu => 'תפריט';

  @override
  String get settings => 'הגדרות';

  @override
  String get newTab => 'כרטיסייה חדשה';

  @override
  String get newPrivateTab => 'כרטיסייה פרטית חדשה';

  @override
  String get privateTab => 'כרטיסייה פרטית';

  @override
  String get bookmarks => 'סימניות';

  @override
  String get history => 'היסטוריה';

  @override
  String get readingList => 'רשימת קריאה';

  @override
  String get downloads => 'הורדות';

  @override
  String get tabs => 'כרטיסיות';

  @override
  String get name => 'שם';

  @override
  String get address => 'כתובת';

  @override
  String get today => 'היום';

  @override
  String get yesterday => 'אתמול';

  @override
  String get privacyReport => 'דוח פרטיות';

  @override
  String downloadStarted(String name) {
    return 'ההורדה של $name התחילה';
  }

  @override
  String get cantDownload => 'אי אפשר להוריד את הקובץ הזה';

  @override
  String savedToDownloads(String name) {
    return '$name נשמר בהורדות';
  }

  @override
  String get show => 'הצגה';

  @override
  String couldntSave(String name) {
    return 'לא ניתן היה לשמור את $name';
  }

  @override
  String get badCertificate =>
      'אישור האבטחה של האתר הזה לא תקין, ולכן הוא לא נפתח.';

  @override
  String get findNoMatches => 'אין תוצאות';

  @override
  String findCount(int active, int count) {
    return '$active מתוך $count';
  }

  @override
  String get openInNewTab => 'פתיחה בכרטיסייה חדשה';

  @override
  String get openInPrivateTab => 'פתיחה בכרטיסייה פרטית';

  @override
  String get openImageInNewTab => 'פתיחת התמונה בכרטיסייה חדשה';

  @override
  String get copyLink => 'העתקת הקישור';

  @override
  String get copyImageAddress => 'העתקת כתובת התמונה';

  @override
  String get openInAnotherAppTitle => 'לפתוח באפליקציה אחרת?';

  @override
  String get externalMail => 'הקישור הזה פותח הודעה חדשה באפליקציית הדואר שלך.';

  @override
  String get externalTel => 'הקישור הזה מחייג למספר באפליקציית הטלפון שלך.';

  @override
  String get externalOther => 'הדף הזה מבקש לפתוח אפליקציה אחרת בטלפון שלך.';

  @override
  String get stayHere => 'להישאר כאן';

  @override
  String get notSecureTitle => 'אתר לא מאובטח';

  @override
  String notSecureBody(String host) {
    return 'האתר $host לא מציע חיבור מאובטח (HTTPS). אם ממשיכים, אחרים ברשת שלך יכולים לראות ולשנות את מה שנשלח ומתקבל באתר הזה.';
  }

  @override
  String get continueAnyway => 'להמשיך בכל זאת';

  @override
  String get goBack => 'חזרה';

  @override
  String permissionAsk(String host, String what) {
    return 'לאפשר לאתר $host להשתמש ב$what?';
  }

  @override
  String get permWhatCamera => 'מצלמה';

  @override
  String get permWhatMicrophone => 'מיקרופון';

  @override
  String get permWhatLocation => 'מיקום';

  @override
  String listAnd(String first, String last) {
    return '$first ו$last';
  }

  @override
  String listComma(String first, String next) {
    return '$first, $next';
  }

  @override
  String get permissionPrivateNote => 'בכרטיסייה פרטית השאלה נשאלת בכל פעם.';

  @override
  String get permissionChangeLater =>
      'אפשר לשנות את זה אחר כך בתפריט האתר (המגן) או בהגדרות > הרשאות אתרים.';

  @override
  String get onlyThisTime => 'רק הפעם';

  @override
  String get readerCant => 'אי אפשר להציג את הדף הזה בתצוגת קריאה';

  @override
  String get readerNeedsJs =>
      'תצוגת קריאה דורשת ש-JavaScript יהיה פעיל באתר הזה';

  @override
  String get addedToReadingList => 'נוסף לרשימת הקריאה';

  @override
  String get addedToReadingListOffline =>
      'נוסף לרשימת הקריאה ונשמר לקריאה בלי חיבור';

  @override
  String get couldntAddReading => 'לא ניתן היה להוסיף לרשימת הקריאה';

  @override
  String get savedCopyUnavailable => 'העותק השמור לא זמין. הדף נפתח במקומו.';

  @override
  String get noHomeShortcuts => 'מסך הבית שלך לא תומך בקיצורי דרך';

  @override
  String get fireTitle => 'לסגור את כל הכרטיסיות ולנקות נתונים?';

  @override
  String get fireBody =>
      'כל הכרטיסיות, הרגילות והפרטיות, ייסגרו, וקובצי Cookie, נתוני אתרים והמטמון יימחקו מהטלפון הזה. החיבור שלך לאתרים ינותק. הסימניות, רשימת הקריאה וההורדות נשארות.';

  @override
  String get fireAlsoHistory => 'למחוק גם את ההיסטוריה ואת דוח הפרטיות';

  @override
  String get rangeLastHour => 'השעה האחרונה';

  @override
  String get rangeLast24 => '24 השעות האחרונות';

  @override
  String get rangeLast7Days => '7 הימים האחרונים';

  @override
  String get rangeAll => 'כל ההיסטוריה';

  @override
  String get fireDone => 'הכרטיסיות נסגרו ונתוני הגלישה נוקו';

  @override
  String get bookmarkAction => 'הוספה לסימניות';

  @override
  String get removeBookmark => 'הסרת הסימנייה';

  @override
  String get bookmarked => 'נוסף לסימניות';

  @override
  String get bookmarkRemoved => 'הסימנייה הוסרה';

  @override
  String get leaveReader => 'יציאה מתצוגת קריאה';

  @override
  String get readerView => 'תצוגת קריאה';

  @override
  String get addToReadingList => 'הוספה לרשימת הקריאה';

  @override
  String get saveAgainReadingList => 'שמירה מחדש ברשימת הקריאה';

  @override
  String get findInPage => 'חיפוש בדף';

  @override
  String get printOrPdf => 'הדפסה או שמירה כ-PDF';

  @override
  String get shareAsQr => 'שיתוף כקוד QR';

  @override
  String get addToHomeScreen => 'הוספה למסך הבית';

  @override
  String get desktopSite => 'אתר למחשב';

  @override
  String get fireMenu => 'סגירת כל הכרטיסיות וניקוי נתונים';

  @override
  String get pageStopped => 'הדף הזה הפסיק לפעול.';

  @override
  String get previous => 'הקודם';

  @override
  String get next => 'הבא';

  @override
  String get siteProtection => 'הגנה באתר';

  @override
  String get addressHint => 'חיפוש או הקלדת כתובת';

  @override
  String get addressHintPrivate => 'כרטיסייה פרטית: חיפוש או הקלדת כתובת';

  @override
  String get voiceSearch => 'חיפוש קולי';

  @override
  String get scanQr => 'סריקת קוד QR';

  @override
  String get privateTooltip =>
      'כרטיסייה פרטית: בלי היסטוריה, קובצי Cookie נמחקים בסגירה';

  @override
  String searchWith(String engine) {
    return 'חיפוש ב-$engine';
  }

  @override
  String get qrPrompt => 'כוונו את המצלמה אל קוד QR';

  @override
  String get voicePrompt => 'אמרו מה לחפש, או כתובת';

  @override
  String get pinToStart => 'הצמדה לדף הפתיחה';

  @override
  String get unpinFromStart => 'ביטול ההצמדה לדף הפתיחה';

  @override
  String get pinnedToStart => 'הוצמד לדף הפתיחה';

  @override
  String get unpinnedFromStart => 'הוסר מדף הפתיחה';

  @override
  String get editThisSearch => 'עריכת החיפוש הזה';

  @override
  String get yourPasswords => 'הסיסמאות שלך';

  @override
  String get passwordsTip =>
      'ZT Browser אף פעם לא שומר סיסמאות. מנהל הסיסמאות שלך (Bitwarden, Proton Pass, 1Password...) ממלא טופסי כניסה דרך המילוי האוטומטי של Android, גם בכרטיסיות פרטיות.';

  @override
  String get chooseInAndroid => 'בחירה ב-Android';

  @override
  String get gotIt => 'הבנתי';

  @override
  String get privateExplain =>
      'דפים שנפתחים כאן לא נשמרים בהיסטוריה. קובצי Cookie ונתוני אתרים נשמרים בנפרד מהכרטיסיות הרגילות, ונמחקים כשסוגרים את הכרטיסייה הפרטית האחרונה או כשהאפליקציה ננעלת. הורדות וסימניות שמוסיפים נשמרות.\n\nכרטיסיות פרטיות מסתירות את הגלישה בטלפון הזה. אתרים, הרשת שלך וספק האינטרנט עדיין יכולים לראות את הביקורים שלך.';

  @override
  String get startBlurb =>
      'מעקב ופרסומות נחסמים בכל אתר. הסימניות וההיסטוריה שלך מוצפנות מקצה לקצה בחשבון Zero-Trust שלך: רק המכשירים שלך יכולים לקרוא אותן.';

  @override
  String get shortcuts => 'קיצורי דרך';

  @override
  String get mostVisited => 'הנצפים ביותר';

  @override
  String get addShortcut => 'הוספת קיצור דרך';

  @override
  String get editShortcut => 'עריכת קיצור הדרך';

  @override
  String get editShortcuts => 'עריכת קיצורי הדרך';

  @override
  String get add => 'הוספה';

  @override
  String get pin => 'הצמדה';

  @override
  String get unpin => 'ביטול ההצמדה';

  @override
  String get dontShowHere => 'לא להציג כאן';

  @override
  String get shortcutInvalid => 'יש להקליד כתובת אתר, למשל example.com';

  @override
  String get shortcutsEmpty =>
      'הצמידו את האתרים שאתם פותחים הכי הרבה. בכל דף, פותחים את התפריט ומקישים על \"הצמדה לדף הפתיחה\", או מוסיפים כאן.';

  @override
  String get dragToReorder => 'לוחצים לחיצה ארוכה וגוררים כדי לשנות את הסדר';

  @override
  String blockedThisWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'השבוע נחסמו $count רכיבי מעקב ופרסומות',
      one: 'השבוע נחסם רכיב מעקב או פרסומת אחד',
    );
    return '$_temp0';
  }

  @override
  String get defaultBrowser => 'דפדפן ברירת המחדל';

  @override
  String get defaultBrowserOn => 'קישורים מאפליקציות אחרות נפתחים ב-ZT Browser';

  @override
  String get defaultBrowserOff =>
      'הקישו כדי שקישורים מאפליקציות אחרות ייפתחו ב-ZT Browser';

  @override
  String get searchEngine => 'מנוע חיפוש';

  @override
  String get privacy => 'פרטיות';

  @override
  String get blockTrackers => 'חסימת מעקב ופרסומות';

  @override
  String blockTrackersCount(String count) {
    return '$count שרתי מעקב ופרסום מוכרים, מתוך EasyList ו-EasyPrivacy';
  }

  @override
  String get blockTrackersNoCount =>
      'שרתי מעקב ופרסום מוכרים, מתוך EasyList ו-EasyPrivacy';

  @override
  String get hideBanners => 'הסתרת חלונות Cookie ותיבות פרסום';

  @override
  String get hideBannersSub =>
      'מסתיר חלונות \"אישור קובצי Cookie\" (בלי לאשר דבר) ואת הרווחים הריקים שפרסומות חסומות משאירות. EasyList Cookie List.';

  @override
  String get stripTracking => 'הסרת מעקב מקישורים';

  @override
  String get stripTrackingSub =>
      'מסיר תגים כמו utm_source ו-fbclid כשפותחים, מעתיקים או משתפים קישור, ומדלג על עותקי AMP של Google ועל דפים שרק מדווחים על הלחיצה שלך לפני שהם מעבירים אותך הלאה.';

  @override
  String get fingerprinting => 'הגנה מפני טביעת אצבע דיגיטלית';

  @override
  String get fingerprintingSub =>
      'מוסיף רעש למידע שאתרים קוראים כדי לזהות את הטלפון שלך (קנבס, שמע, שבב גרפי, זיכרון), שונה בכל אתר ובכל פתיחה של האפליקציה.';

  @override
  String get httpsOnly => 'HTTPS בלבד';

  @override
  String get httpsOnlySub =>
      'פתיחת אתרים בחיבור מאובטח, ושאלה לפני טעינת אתר שפועל רק בלי הצפנה';

  @override
  String get blocklistUpdates => 'עדכוני רשימת החסימה';

  @override
  String get blocklistUpdatesSub =>
      'מורדת פעם בשבוע מהגרסאות של ZT Browser ב-GitHub ונבדקת מול החתימה שלה. הקישו כדי לבדוק עכשיו.';

  @override
  String blocklistUpdatesSubDated(String date) {
    return 'מורדת פעם בשבוע מהגרסאות של ZT Browser ב-GitHub ונבדקת מול החתימה שלה. הרשימה מתאריך $date. הקישו כדי לבדוק עכשיו.';
  }

  @override
  String get sitePermissions => 'הרשאות אתרים';

  @override
  String get sitePermissionsNone =>
      'אתרים שואלים לפני שימוש במצלמה, במיקרופון או במיקום';

  @override
  String sitePermissionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count אתרים עם תשובה שמורה',
      one: 'אתר אחד עם תשובה שמורה',
    );
    return '$_temp0';
  }

  @override
  String get sitesWithoutProtection => 'אתרים בלי הגנה';

  @override
  String get sitesWithoutProtectionExplain =>
      'מעקב ופרסומות לא נחסמים באתרים האלה.';

  @override
  String get protect => 'הפעלת הגנה';

  @override
  String get javascriptOff => 'JavaScript כבוי';

  @override
  String get javascriptOffExplain => 'JavaScript לא פועל באתרים האלה.';

  @override
  String get turnOn => 'הפעלה';

  @override
  String get passwordManager => 'מנהל סיסמאות';

  @override
  String get autofillUnsupported => 'הטלפון הזה לא תומך במילוי אוטומטי';

  @override
  String autofillActive(String name) {
    return '$name ממלא סיסמאות ב-ZT Browser, גם בכרטיסיות פרטיות. ZT Browser אף פעם לא שומר סיסמאות.';
  }

  @override
  String get autofillPick =>
      'בחרו מנהל סיסמאות (Bitwarden, Proton Pass, 1Password...) בהגדרות Android כדי למלא טופסי כניסה. ZT Browser לא שומר סיסמאות בעצמו.';

  @override
  String get pagesSection => 'דפים';

  @override
  String get textSize => 'גודל הטקסט';

  @override
  String get darkPages => 'דפים כהים';

  @override
  String get darkPagesSub =>
      'כשהטלפון במצב כהה, להכהות אתרים שאין להם עיצוב כהה משלהם';

  @override
  String get tabsAndHistory => 'כרטיסיות והיסטוריה';

  @override
  String get closeUnusedTabs => 'סגירת כרטיסיות שלא בשימוש';

  @override
  String get keepHistory => 'שמירת היסטוריה';

  @override
  String get clearCookies => 'ניקוי קובצי Cookie ונתוני אתרים';

  @override
  String get clearCookiesSub => 'מנתק אותך מאתרים בטלפון הזה';

  @override
  String get alwaysOn => 'תמיד פעיל';

  @override
  String get alwaysOnSub =>
      'קובצי Cookie של צד שלישי חסומים. נשלח אות Global Privacy Control, שמורה לאתרים לא למכור ולא לשתף את המידע שלך. מצלמה, מיקרופון ומיקום רק אחרי אישור שלך לאתר. מנוע הגלישה לא שולח נתוני שימוש.';

  @override
  String get credits => 'קרדיטים לקוד פתוח';

  @override
  String get creditsSub =>
      'EasyList, EasyPrivacy ו-EasyList Cookie List מאת The EasyList authors (easylist.to), בשימוש לפי רישיון CC BY-SA 3.0. תצוגת קריאה: Mozilla Readability (Apache 2.0). סורק QR: ZXing (Apache 2.0).';

  @override
  String get keepHistoryExplain =>
      'דפים ישנים יותר נמחקים מההיסטוריה בכל המכשירים שלך.';

  @override
  String get closeTabsExplain =>
      'כרטיסיות שלא נפתחו במשך הזמן הזה נסגרות מעצמן. כרטיסיות פרטיות נסגרות תמיד כשהאפליקציה ננעלת.';

  @override
  String get checkingBlocklist => 'בודק אם יש רשימת חסימה חדשה…';

  @override
  String get blocklistUpdated => 'רשימת החסימה עודכנה';

  @override
  String get blocklistUpToDate => 'רשימת החסימה מעודכנת';

  @override
  String get blocklistFailed => 'לא ניתן לבדוק עכשיו. נסו שוב מאוחר יותר.';

  @override
  String get clearCookiesTitle => 'לנקות קובצי Cookie ונתוני אתרים?';

  @override
  String get clearCookiesBody =>
      'החיבור שלך לאתרים בטלפון הזה ינותק. הסימניות וההיסטוריה נשארות.';

  @override
  String get cookiesCleared => 'קובצי Cookie ונתוני אתרים נוקו';

  @override
  String get historyNone => 'לא לשמור היסטוריה';

  @override
  String get forever => 'לתמיד';

  @override
  String get oneWeek => 'שבוע';

  @override
  String get oneMonth => 'חודש';

  @override
  String get threeMonths => '3 חודשים';

  @override
  String get oneYear => 'שנה';

  @override
  String nDays(int count) {
    return '$count ימים';
  }

  @override
  String get never => 'אף פעם';

  @override
  String get afterDay => 'אחרי יום';

  @override
  String get afterWeek => 'אחרי שבוע';

  @override
  String get afterTwoWeeks => 'אחרי שבועיים';

  @override
  String get afterMonth => 'אחרי חודש';

  @override
  String afterDays(int count) {
    return 'אחרי $count ימים';
  }

  @override
  String get searchSuggestions => 'הצעות חיפוש';

  @override
  String get searchSuggestionsOff =>
      'כבוי: שום דבר שמקלידים לא נשלח לשום מקום עד שמחפשים.';

  @override
  String searchSuggestionsOn(String engine) {
    return 'מה שמקלידים בשורת הכתובת נשלח אל $engine תוך כדי הקלדה. אף פעם לא כתובות, ואף פעם לא בכרטיסיות פרטיות.';
  }

  @override
  String searchSuggestionsNone(String engine) {
    return '$engine לא מציע הצעות חיפוש.';
  }

  @override
  String get searchSuggestionsAskTitle => 'להפעיל הצעות חיפוש?';

  @override
  String searchSuggestionsAskBody(String engine) {
    return 'תוך כדי הקלדה בשורת הכתובת, האותיות נשלחות אל $engine כדי שיציע חיפושים. כך הוא יודע מה הקלדת גם אם לא חיפשת את זה בסוף. כתובות וכרטיסיות פרטיות לא נשלחות אף פעם.';
  }

  @override
  String get addSearchEngine => 'הוספת מנוע חיפוש';

  @override
  String get engineAddress => 'כתובת החיפוש, עם %s במקום מילות החיפוש';

  @override
  String get engineInvalid => 'יש להקליד שם וכתובת אתר שמכילה %s';

  @override
  String removeEngine(String name) {
    return 'הסרת $name';
  }

  @override
  String get startPageSection => 'דף הפתיחה';

  @override
  String get showMostVisited => 'הצגת האתרים הנצפים ביותר';

  @override
  String get showMostVisitedSub => 'מתוך ההיסטוריה שלך, בדף הפתיחה';

  @override
  String get privacyReportSub =>
      'סופר את רכיבי המעקב והפרסומות שנחסמו בכל אתר. נשמר כמו ההיסטוריה שלך: מוצפן מקצה לקצה בחשבון שלך.';

  @override
  String reportWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count רכיבי מעקב ופרסומות נחסמו ב-7 הימים האחרונים',
      one: 'רכיב מעקב או פרסומת אחד נחסם ב-7 הימים האחרונים',
      zero: 'לא נחסם דבר ב-7 הימים האחרונים',
    );
    return '$_temp0';
  }

  @override
  String reportMonth(int days, int count) {
    return '$days הימים האחרונים: $count';
  }

  @override
  String get reportTopSites => 'האתרים שבהם נחסם הכי הרבה השבוע';

  @override
  String get reportEmpty => 'עדיין לא נספר דבר. גלשו קצת וחזרו לכאן.';

  @override
  String get reportOff => 'דוח הפרטיות כבוי. המעקב עדיין נחסם, רק לא נספר.';

  @override
  String get reportClear => 'ניקוי הדוח';

  @override
  String get reportCleared => 'דוח הפרטיות נוקה';

  @override
  String get reportNote =>
      'נספר במכשירים שלך ונשמר מוצפן מקצה לקצה בחשבון שלך, כמו ההיסטוריה. כרטיסיות פרטיות מוסיפות לסך הכול בלי שם האתר.';

  @override
  String get reportNoSites => 'שמות אתרים לא נשמרים כשההיסטוריה כבויה.';

  @override
  String reportCountOnSite(int count) {
    return '$count נחסמו';
  }

  @override
  String get newGroup => 'קבוצה חדשה';

  @override
  String get removeFromGroup => 'הסרה מהקבוצה';

  @override
  String get groupName => 'שם הקבוצה';

  @override
  String get newTabInGroup => 'כרטיסייה חדשה בקבוצה הזאת';

  @override
  String get renameGroup => 'שינוי שם הקבוצה';

  @override
  String get ungroupTabs => 'פירוק הקבוצה';

  @override
  String closeNTabs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'סגירת $count כרטיסיות',
      one: 'סגירת כרטיסייה אחת',
    );
    return '$_temp0';
  }

  @override
  String get searchTabs => 'חיפוש בכרטיסיות';

  @override
  String get stopSearching => 'סיום החיפוש';

  @override
  String get closeAllPrivateTabs => 'סגירת כל הכרטיסיות הפרטיות';

  @override
  String get closeAllTabs => 'סגירת כל הכרטיסיות';

  @override
  String tabsCount(int count) {
    return 'כרטיסיות ($count)';
  }

  @override
  String privateCount(int count) {
    return 'פרטיות ($count)';
  }

  @override
  String get otherDevices => 'מכשירים אחרים';

  @override
  String get noOpenTabs => 'אין כרטיסיות פתוחות';

  @override
  String get privateTabsExplain =>
      'כרטיסיות פרטיות לא שומרות היסטוריה, וקובצי ה-Cookie שלהן נמחקים כשהאחרונה נסגרת או כשהאפליקציה ננעלת.';

  @override
  String get noTabsMatch => 'אין כרטיסיות מתאימות.';

  @override
  String get notInGroup => 'לא בקבוצה';

  @override
  String nTabs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count כרטיסיות',
      one: 'כרטיסייה אחת',
    );
    return '$_temp0';
  }

  @override
  String get groupOptions => 'אפשרויות הקבוצה';

  @override
  String get closeTab => 'סגירת הכרטיסייה';

  @override
  String get otherDevicesEmpty =>
      'כרטיסיות שפתוחות ב-ZT Browser במכשירים האחרים שלך מוצגות כאן, מוצפנות מקצה לקצה. כרטיסיות פרטיות לא משותפות אף פעם.';

  @override
  String get editBookmark => 'עריכת הסימנייה';

  @override
  String get importBookmarks => 'ייבוא סימניות';

  @override
  String get importExplain =>
      'בחרו את קובץ הסימניות שייצאתם מהדפדפן האחר:\n\n• Chrome או Edge: סימניות > מנהל הסימניות > ⋮ > ייצוא סימניות (במחשב).\n• Firefox: סימניות > ניהול סימניות > ייבוא וגיבוי > ייצוא סימניות ל-HTML.\n\nהקובץ נשאר בטלפון הזה; הסימניות מוצפנות מקצה לקצה בחשבון שלך.';

  @override
  String get pickFile => 'בחירת קובץ';

  @override
  String get noBookmarksInFile => 'לא נמצאו סימניות בקובץ הזה';

  @override
  String allAlreadySaved(int count) {
    return 'כל $count הסימניות כבר היו שמורות';
  }

  @override
  String importedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'יובאו $count סימניות',
      one: 'יובאה סימנייה אחת',
    );
    return '$_temp0';
  }

  @override
  String get searchBookmarks => 'חיפוש בסימניות';

  @override
  String get noBookmarksYet =>
      'עדיין אין סימניות. מקישים על הכוכב בתפריט כדי לשמור דף. הסימניות מוצפנות מקצה לקצה וזמינות בכל המכשירים שלך.';

  @override
  String get noBookmarksMatch => 'אין סימניות מתאימות.';

  @override
  String daysAgo(int count) {
    return 'לפני $count ימים';
  }

  @override
  String get clearHistory => 'ניקוי היסטוריה';

  @override
  String get historyCleared => 'ההיסטוריה נוקתה בכל המכשירים שלך';

  @override
  String get searchHistory => 'חיפוש בהיסטוריה';

  @override
  String get historyOff =>
      'ההיסטוריה כבויה. אפשר להפעיל אותה בהגדרות, תחת שמירת היסטוריה.';

  @override
  String get historyEmpty =>
      'דפים שביקרת בהם מוצגים כאן, מוצפנים מקצה לקצה. כרטיסיות פרטיות לא נשמרות אף פעם.';

  @override
  String get nothingMatches => 'אין תוצאות מתאימות.';

  @override
  String sizeBytes(int count) {
    return '$count בייטים';
  }

  @override
  String get fileFallbackName => 'קובץ';

  @override
  String get noAppOpens => 'אין בטלפון הזה אפליקציה שפותחת קובץ מהסוג הזה';

  @override
  String get cancelDownloadTitle => 'לבטל את ההורדה?';

  @override
  String get deleteFileTitle => 'למחוק את הקובץ?';

  @override
  String stopsDownloading(String name) {
    return 'ההורדה של $name תיפסק.';
  }

  @override
  String deletedFromPhone(String name) {
    return '$name יימחק מהטלפון הזה.';
  }

  @override
  String get keep => 'להשאיר';

  @override
  String get cancelDownload => 'ביטול ההורדה';

  @override
  String get downloadsEmpty =>
      'קבצים שמורידים מוצגים כאן. הם נשמרים בתיקיית ההורדות של הטלפון.';

  @override
  String progressOf(String done, String total) {
    return '$done מתוך $total';
  }

  @override
  String get downloadingEllipsis => 'מוריד…';

  @override
  String get waitingConnection => 'ממתין לחיבור';

  @override
  String get couldntDownload => 'ההורדה נכשלה';

  @override
  String get cantShare => 'אי אפשר לשתף את הקובץ הזה';

  @override
  String get readingListError => 'לא ניתן היה לטעון את רשימת הקריאה.';

  @override
  String get readingListEmpty =>
      'שומרים דפים מהתפריט עם \"הוספה לרשימת הקריאה\". מאמרים נשמרים לקריאה בלי חיבור, מוצפנים מקצה לקצה בחשבון שלך.';

  @override
  String get savedOffline => 'שמור לקריאה בלי חיבור';

  @override
  String get openSavedCopy => 'פתיחת העותק השמור';

  @override
  String get markUnread => 'סימון כלא נקרא';

  @override
  String get markRead => 'סימון כנקרא';

  @override
  String get savedCopy => 'עותק שמור';

  @override
  String get permCamera => 'מצלמה';

  @override
  String get permMicrophone => 'מיקרופון';

  @override
  String get permLocation => 'מיקום';

  @override
  String permOnHost(String kind, String host) {
    return '$kind באתר $host';
  }

  @override
  String get askNextTime => 'לשאול בפעם הבאה';

  @override
  String get sitePermsEmpty =>
      'כשאתר מבקש את המצלמה, המיקרופון או המיקום שלך, ZT Browser שואל אותך קודם. תשובות שבחרת לזכור מוצגות כאן.';

  @override
  String permAllowedChip(String kind) {
    return '$kind: מאושר';
  }

  @override
  String permBlockedChip(String kind) {
    return '$kind: חסום';
  }

  @override
  String get forget => 'שכחה';

  @override
  String get allowed => 'מאושר';

  @override
  String get blocked => 'חסום';

  @override
  String get connectionSecure => 'החיבור מאובטח';

  @override
  String get connectionNotSecure => 'החיבור לא מאובטח';

  @override
  String get connectionSecureSub => 'מה שנשלח ומוצג באתר הזה מוצפן בדרך.';

  @override
  String get connectionNotSecureSub =>
      'אחרים ברשת שלך יכולים לראות ולשנות את הדף הזה. אין להזין כאן סיסמאות או מספרי כרטיס.';

  @override
  String blockedOnPage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'נחסמו $count רכיבי מעקב ופרסומות',
      one: 'נחסם רכיב מעקב או פרסומת אחד',
    );
    return '$_temp0';
  }

  @override
  String get blockedOnPageSub => 'בדף הזה, לפי EasyList ו-EasyPrivacy.';

  @override
  String protectionOn(String site) {
    return 'הגנה באתר $site';
  }

  @override
  String get protectionSub => 'לכבות רק אם האתר לא עובד. הדף ייטען מחדש.';

  @override
  String get trackerBlockingOff => 'חסימת המעקב כבויה';

  @override
  String get turnOnInSettings => 'אפשר להפעיל אותה בהגדרות.';

  @override
  String javascriptOn(String site) {
    return 'JavaScript באתר $site';
  }

  @override
  String get javascriptSub =>
      'כיבוי הופך אתרים רבים לפשוטים יותר ומקשה לעקוב אחריך, אבל חלקם מפסיקים לעבוד. הדף ייטען מחדש.';

  @override
  String qrFor(String url) {
    return 'קוד QR עבור $url';
  }

  @override
  String get shareLink => 'שיתוף הקישור';
}
