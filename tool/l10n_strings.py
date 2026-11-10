#!/usr/bin/env python3
"""The app's texts in English and Hebrew, in one table.

Run `python3 tool/l10n_strings.py` after changing a text: it writes
lib/l10n/app_en.arb and lib/l10n/app_he.arb, and `flutter gen-l10n` (or any
`flutter pub get`) turns those into lib/l10n/generated/.

Each row: key, English, Hebrew. `{name}` is filled in by the app; a row
with `{count, plural, ...}` picks a form by number.
"""
import json
import os
import re

S = [
    # ---- Common ----
    ("cancel", "Cancel", "ביטול"),
    ("save", "Save", "שמירה"),
    ("delete", "Delete", "מחיקה"),
    ("clear", "Clear", "ניקוי"),
    ("open", "Open", "פתיחה"),
    ("share", "Share", "שיתוף"),
    ("edit", "Edit", "עריכה"),
    ("remove", "Remove", "הסרה"),
    ("undo", "Undo", "ביטול הפעולה"),
    ("allow", "Allow", "אישור"),
    ("block", "Block", "חסימה"),
    ("copied", "Copied", "הועתק"),
    ("more", "More", "עוד"),
    ("close", "Close", "סגירה"),
    ("reload", "Reload", "טעינה מחדש"),
    ("back", "Back", "חזרה"),
    ("forward", "Forward", "קדימה"),
    ("home", "Home", "דף הבית"),
    ("menu", "Menu", "תפריט"),
    ("settings", "Settings", "הגדרות"),
    ("newTab", "New tab", "כרטיסייה חדשה"),
    ("newPrivateTab", "New private tab", "כרטיסייה פרטית חדשה"),
    ("privateTab", "Private tab", "כרטיסייה פרטית"),
    ("bookmarks", "Bookmarks", "סימניות"),
    ("history", "History", "היסטוריה"),
    ("readingList", "Reading list", "רשימת קריאה"),
    ("downloads", "Downloads", "הורדות"),
    ("tabs", "Tabs", "כרטיסיות"),
    ("name", "Name", "שם"),
    ("address", "Address", "כתובת"),
    ("today", "Today", "היום"),
    ("yesterday", "Yesterday", "אתמול"),
    ("privacyReport", "Privacy report", "דוח פרטיות"),

    # ---- Browser screen ----
    ("downloadStarted", "Downloading {name}", "ההורדה של {name} התחילה"),
    ("cantDownload", "This file can't be downloaded", "אי אפשר להוריד את הקובץ הזה"),
    ("savedToDownloads", "Saved {name} to Downloads", "{name} נשמר בהורדות"),
    ("show", "Show", "הצגה"),
    ("couldntSave", "{name} couldn't be saved", "לא ניתן היה לשמור את {name}"),
    ("badCertificate",
     "This site's security certificate isn't valid, so it was not opened.",
     "אישור האבטחה של האתר הזה לא תקין, ולכן הוא לא נפתח."),
    ("findNoMatches", "No matches", "אין תוצאות"),
    ("findCount", "{active} of {count}", "{active} מתוך {count}"),
    ("openInNewTab", "Open in new tab", "פתיחה בכרטיסייה חדשה"),
    ("openInPrivateTab", "Open in private tab", "פתיחה בכרטיסייה פרטית"),
    ("openImageInNewTab", "Open image in new tab", "פתיחת התמונה בכרטיסייה חדשה"),
    ("copyLink", "Copy link", "העתקת הקישור"),
    ("copyImageAddress", "Copy image address", "העתקת כתובת התמונה"),
    ("openInAnotherAppTitle", "Open in another app?", "לפתוח באפליקציה אחרת?"),
    ("externalMail", "This link writes an email in your mail app.",
     "הקישור הזה פותח הודעה חדשה באפליקציית הדואר שלך."),
    ("externalTel", "This link calls a number with your phone app.",
     "הקישור הזה מחייג למספר באפליקציית הטלפון שלך."),
    ("externalOther", "This page wants to open another app on your phone.",
     "הדף הזה מבקש לפתוח אפליקציה אחרת בטלפון שלך."),
    ("stayHere", "Stay here", "להישאר כאן"),
    ("notSecureTitle", "Not a secure site", "אתר לא מאובטח"),
    ("notSecureBody",
     "{host} doesn't offer a secure (HTTPS) connection. If you continue, "
     "others on your network can see and change what you send and receive "
     "on this site.",
     "האתר {host} לא מציע חיבור מאובטח (HTTPS). אם ממשיכים, אחרים ברשת שלך "
     "יכולים לראות ולשנות את מה שנשלח ומתקבל באתר הזה."),
    ("continueAnyway", "Continue anyway", "להמשיך בכל זאת"),
    ("goBack", "Go back", "חזרה"),
    ("permissionAsk", "Allow {host} to use your {what}?",
     "לאפשר לאתר {host} להשתמש ב{what}?"),
    ("permWhatCamera", "camera", "מצלמה"),
    ("permWhatMicrophone", "microphone", "מיקרופון"),
    ("permWhatLocation", "location", "מיקום"),
    ("listAnd", "{first} and {last}", "{first} ו{last}"),
    ("listComma", "{first}, {next}", "{first}, {next}"),
    ("permissionPrivateNote", "This private tab asks every time.",
     "בכרטיסייה פרטית השאלה נשאלת בכל פעם."),
    ("permissionChangeLater",
     "You can change this later in the site menu (the shield) or in "
     "Settings > Site permissions.",
     "אפשר לשנות את זה אחר כך בתפריט האתר (המגן) או בהגדרות > הרשאות אתרים."),
    ("onlyThisTime", "Only this time", "רק הפעם"),
    ("readerCant", "This page can't be shown in reader view",
     "אי אפשר להציג את הדף הזה בתצוגת קריאה"),
    ("readerNeedsJs", "Reader view needs JavaScript on for this site",
     "תצוגת קריאה דורשת ש-JavaScript יהיה פעיל באתר הזה"),
    ("addedToReadingList", "Added to reading list", "נוסף לרשימת הקריאה"),
    ("addedToReadingListOffline",
     "Added to reading list, saved to read offline",
     "נוסף לרשימת הקריאה ונשמר לקריאה בלי חיבור"),
    ("couldntAddReading", "Couldn't add to the reading list",
     "לא ניתן היה להוסיף לרשימת הקריאה"),
    ("savedCopyUnavailable",
     "The saved copy isn't available. Opening the page instead.",
     "העותק השמור לא זמין. הדף נפתח במקומו."),
    ("noHomeShortcuts", "Your home screen doesn't accept shortcuts",
     "מסך הבית שלך לא תומך בקיצורי דרך"),
    ("fireTitle", "Close all tabs and clear data?",
     "לסגור את כל הכרטיסיות ולנקות נתונים?"),
    ("fireBody",
     "Closes every tab, normal and private, and deletes cookies, site data "
     "and the cache on this phone. You are signed out of websites. "
     "Bookmarks, the reading list and downloads stay.",
     "כל הכרטיסיות, הרגילות והפרטיות, ייסגרו, וקובצי Cookie, נתוני אתרים "
     "והמטמון יימחקו מהטלפון הזה. החיבור שלך לאתרים ינותק. הסימניות, רשימת "
     "הקריאה וההורדות נשארות."),
    ("fireAlsoHistory", "Also delete history and the privacy report",
     "למחוק גם את ההיסטוריה ואת דוח הפרטיות"),
    ("rangeLastHour", "Last hour", "השעה האחרונה"),
    ("rangeLast24", "Last 24 hours", "24 השעות האחרונות"),
    ("rangeLast7Days", "Last 7 days", "7 הימים האחרונים"),
    ("rangeAll", "All history", "כל ההיסטוריה"),
    ("fireDone", "Tabs closed and browsing data cleared",
     "הכרטיסיות נסגרו ונתוני הגלישה נוקו"),
    ("bookmarkAction", "Bookmark", "הוספה לסימניות"),
    ("removeBookmark", "Remove bookmark", "הסרת הסימנייה"),
    ("bookmarked", "Bookmarked", "נוסף לסימניות"),
    ("bookmarkRemoved", "Bookmark removed", "הסימנייה הוסרה"),
    ("leaveReader", "Leave reader view", "יציאה מתצוגת קריאה"),
    ("readerView", "Reader view", "תצוגת קריאה"),
    ("addToReadingList", "Add to reading list", "הוספה לרשימת הקריאה"),
    ("saveAgainReadingList", "Save again to reading list",
     "שמירה מחדש ברשימת הקריאה"),
    ("findInPage", "Find in page", "חיפוש בדף"),
    ("printOrPdf", "Print or save as PDF", "הדפסה או שמירה כ-PDF"),
    ("shareAsQr", "Share as QR code", "שיתוף כקוד QR"),
    ("addToHomeScreen", "Add to home screen", "הוספה למסך הבית"),
    ("desktopSite", "Desktop site", "אתר למחשב"),
    ("fireMenu", "Close all tabs and clear data",
     "סגירת כל הכרטיסיות וניקוי נתונים"),
    ("pageStopped", "This page stopped working.", "הדף הזה הפסיק לפעול."),
    ("previous", "Previous", "הקודם"),
    ("next", "Next", "הבא"),
    ("siteProtection", "Site protection", "הגנה באתר"),
    ("addressHint", "Search or type an address", "חיפוש או הקלדת כתובת"),
    ("addressHintPrivate", "Private tab: search or type an address",
     "כרטיסייה פרטית: חיפוש או הקלדת כתובת"),
    ("voiceSearch", "Voice search", "חיפוש קולי"),
    ("scanQr", "Scan QR code", "סריקת קוד QR"),
    ("privateTooltip", "Private tab: no history, cookies cleared on close",
     "כרטיסייה פרטית: בלי היסטוריה, קובצי Cookie נמחקים בסגירה"),
    ("searchWith", "Search with {engine}", "חיפוש ב-{engine}"),
    ("qrPrompt", "Point at a QR code", "כוונו את המצלמה אל קוד QR"),
    ("voicePrompt", "Search or say an address", "אמרו מה לחפש, או כתובת"),
    ("pinToStart", "Pin to start page", "הצמדה לדף הפתיחה"),
    ("unpinFromStart", "Unpin from start page", "ביטול ההצמדה לדף הפתיחה"),
    ("pinnedToStart", "Pinned to the start page", "הוצמד לדף הפתיחה"),
    ("unpinnedFromStart", "Removed from the start page", "הוסר מדף הפתיחה"),
    ("editThisSearch", "Edit this search", "עריכת החיפוש הזה"),

    # ---- Start page ----
    ("yourPasswords", "Your passwords", "הסיסמאות שלך"),
    ("passwordsTip",
     "ZT Browser never stores passwords. Your password manager (Bitwarden, "
     "Proton Pass, 1Password...) fills sign-in forms through Android's "
     "autofill, in private tabs too.",
     "ZT Browser אף פעם לא שומר סיסמאות. מנהל הסיסמאות שלך (Bitwarden, "
     "Proton Pass, 1Password...) ממלא טופסי כניסה דרך המילוי האוטומטי של "
     "Android, גם בכרטיסיות פרטיות."),
    ("chooseInAndroid", "Choose in Android", "בחירה ב-Android"),
    ("gotIt", "Got it", "הבנתי"),
    ("privateExplain",
     "Pages you open here are not saved to your history. Cookies and site "
     "data are kept apart from your normal tabs and deleted when you close "
     "the last private tab or the app locks. Downloads and bookmarks you "
     "add are kept.\n\nPrivate tabs hide your browsing on this phone. "
     "Sites, your network and your internet provider can still see your "
     "visits.",
     "דפים שנפתחים כאן לא נשמרים בהיסטוריה. קובצי Cookie ונתוני אתרים "
     "נשמרים בנפרד מהכרטיסיות הרגילות, ונמחקים כשסוגרים את הכרטיסייה "
     "הפרטית האחרונה או כשהאפליקציה ננעלת. הורדות וסימניות שמוסיפים "
     "נשמרות.\n\nכרטיסיות פרטיות מסתירות את הגלישה בטלפון הזה. אתרים, "
     "הרשת שלך וספק האינטרנט עדיין יכולים לראות את הביקורים שלך."),
    ("startBlurb",
     "Trackers and ads are blocked on every site. Your bookmarks and "
     "history are end-to-end encrypted in your Zero-Trust account: only "
     "your devices can read them.",
     "מעקב ופרסומות נחסמים בכל אתר. הסימניות וההיסטוריה שלך מוצפנות מקצה "
     "לקצה בחשבון Zero-Trust שלך: רק המכשירים שלך יכולים לקרוא אותן."),
    ("shortcuts", "Shortcuts", "קיצורי דרך"),
    ("mostVisited", "Most visited", "הנצפים ביותר"),
    ("addShortcut", "Add shortcut", "הוספת קיצור דרך"),
    ("editShortcut", "Edit shortcut", "עריכת קיצור הדרך"),
    ("editShortcuts", "Edit shortcuts", "עריכת קיצורי הדרך"),
    ("add", "Add", "הוספה"),
    ("pin", "Pin", "הצמדה"),
    ("unpin", "Unpin", "ביטול ההצמדה"),
    ("dontShowHere", "Don't show here", "לא להציג כאן"),
    ("shortcutInvalid", "Type a web address, like example.com",
     "יש להקליד כתובת אתר, למשל example.com"),
    ("shortcutsEmpty",
     "Pin the sites you open most. On any page, open the menu and tap "
     "\"Pin to start page\", or add one here.",
     "הצמידו את האתרים שאתם פותחים הכי הרבה. בכל דף, פותחים את התפריט "
     "ומקישים על \"הצמדה לדף הפתיחה\", או מוסיפים כאן."),
    ("dragToReorder", "Hold and drag to change the order",
     "לוחצים לחיצה ארוכה וגוררים כדי לשנות את הסדר"),
    ("blockedThisWeek",
     "{count, plural, =1{1 tracker or ad blocked this week} "
     "other{{count} trackers and ads blocked this week}}",
     "{count, plural, =1{השבוע נחסם רכיב מעקב או פרסומת אחד} "
     "other{השבוע נחסמו {count} רכיבי מעקב ופרסומות}}"),

    # ---- Settings ----
    ("defaultBrowser", "Default browser", "דפדפן ברירת המחדל"),
    ("defaultBrowserOn", "Links from other apps open in ZT Browser",
     "קישורים מאפליקציות אחרות נפתחים ב-ZT Browser"),
    ("defaultBrowserOff", "Tap to open links from other apps in ZT Browser",
     "הקישו כדי שקישורים מאפליקציות אחרות ייפתחו ב-ZT Browser"),
    ("searchEngine", "Search engine", "מנוע חיפוש"),
    ("privacy", "Privacy", "פרטיות"),
    ("blockTrackers", "Block trackers and ads", "חסימת מעקב ופרסומות"),
    ("blockTrackersCount",
     "{count} known tracker and ad hosts, from EasyList and EasyPrivacy",
     "{count} שרתי מעקב ופרסום מוכרים, מתוך EasyList ו-EasyPrivacy"),
    ("blockTrackersNoCount",
     "Known tracker and ad hosts, from EasyList and EasyPrivacy",
     "שרתי מעקב ופרסום מוכרים, מתוך EasyList ו-EasyPrivacy"),
    ("hideBanners", "Hide cookie banners and ad boxes",
     "הסתרת חלונות Cookie ותיבות פרסום"),
    ("hideBannersSub",
     "Hides \"accept cookies\" pop-ups (without accepting anything) and the "
     "empty spaces blocked ads leave. EasyList Cookie List.",
     "מסתיר חלונות \"אישור קובצי Cookie\" (בלי לאשר דבר) ואת הרווחים הריקים "
     "שפרסומות חסומות משאירות. EasyList Cookie List."),
    ("stripTracking", "Remove tracking from links", "הסרת מעקב מקישורים"),
    ("stripTrackingSub",
     "Removes tags like utm_source and fbclid when you open, copy or share "
     "a link, and skips Google AMP copies and pages that only report your "
     "click before sending you on.",
     "מסיר תגים כמו utm_source ו-fbclid כשפותחים, מעתיקים או משתפים קישור, "
     "ומדלג על עותקי AMP של Google ועל דפים שרק מדווחים על הלחיצה שלך לפני "
     "שהם מעבירים אותך הלאה."),
    ("fingerprinting", "Fingerprinting protection",
     "הגנה מפני טביעת אצבע דיגיטלית"),
    ("fingerprintingSub",
     "Adds noise to what sites read to recognise your phone (canvas, audio, "
     "graphics chip, memory), different on every site and every time you "
     "open the app.",
     "מוסיף רעש למידע שאתרים קוראים כדי לזהות את הטלפון שלך (קנבס, שמע, "
     "שבב גרפי, זיכרון), שונה בכל אתר ובכל פתיחה של האפליקציה."),
    ("httpsOnly", "HTTPS-only", "HTTPS בלבד"),
    ("httpsOnlySub",
     "Open sites securely, and ask before loading one that only works "
     "without encryption",
     "פתיחת אתרים בחיבור מאובטח, ושאלה לפני טעינת אתר שפועל רק בלי הצפנה"),
    ("blocklistUpdates", "Blocklist updates", "עדכוני רשימת החסימה"),
    ("blocklistUpdatesSub",
     "Downloaded weekly from ZT Browser's releases on GitHub and checked "
     "against its signature. Tap to check now.",
     "מורדת פעם בשבוע מהגרסאות של ZT Browser ב-GitHub ונבדקת מול החתימה "
     "שלה. הקישו כדי לבדוק עכשיו."),
    ("blocklistUpdatesSubDated",
     "Downloaded weekly from ZT Browser's releases on GitHub and checked "
     "against its signature. List from {date}. Tap to check now.",
     "מורדת פעם בשבוע מהגרסאות של ZT Browser ב-GitHub ונבדקת מול החתימה "
     "שלה. הרשימה מתאריך {date}. הקישו כדי לבדוק עכשיו."),
    ("sitePermissions", "Site permissions", "הרשאות אתרים"),
    ("sitePermissionsNone",
     "Sites ask before using your camera, microphone or location",
     "אתרים שואלים לפני שימוש במצלמה, במיקרופון או במיקום"),
    ("sitePermissionsCount",
     "{count, plural, =1{1 site with a remembered answer} "
     "other{{count} sites with a remembered answer}}",
     "{count, plural, =1{אתר אחד עם תשובה שמורה} "
     "other{{count} אתרים עם תשובה שמורה}}"),
    ("sitesWithoutProtection", "Sites without protection", "אתרים בלי הגנה"),
    ("sitesWithoutProtectionExplain",
     "Trackers and ads are not blocked on these sites.",
     "מעקב ופרסומות לא נחסמים באתרים האלה."),
    ("protect", "Protect", "הפעלת הגנה"),
    ("javascriptOff", "JavaScript off", "JavaScript כבוי"),
    ("javascriptOffExplain", "JavaScript does not run on these sites.",
     "JavaScript לא פועל באתרים האלה."),
    ("turnOn", "Turn on", "הפעלה"),
    ("passwordManager", "Password manager", "מנהל סיסמאות"),
    ("autofillUnsupported", "This phone doesn't support autofill",
     "הטלפון הזה לא תומך במילוי אוטומטי"),
    ("autofillActive",
     "{name} fills passwords in ZT Browser, in private tabs too. ZT Browser "
     "never saves passwords.",
     "{name} ממלא סיסמאות ב-ZT Browser, גם בכרטיסיות פרטיות. ZT Browser אף "
     "פעם לא שומר סיסמאות."),
    ("autofillPick",
     "Pick a password manager (Bitwarden, Proton Pass, 1Password...) in "
     "Android settings to fill sign-in forms. ZT Browser never saves "
     "passwords itself.",
     "בחרו מנהל סיסמאות (Bitwarden, Proton Pass, 1Password...) בהגדרות "
     "Android כדי למלא טופסי כניסה. ZT Browser לא שומר סיסמאות בעצמו."),
    ("pagesSection", "Pages", "דפים"),
    ("textSize", "Text size", "גודל הטקסט"),
    ("darkPages", "Dark pages", "דפים כהים"),
    ("darkPagesSub",
     "When your phone is in dark mode, darken sites that have no dark "
     "design of their own",
     "כשהטלפון במצב כהה, להכהות אתרים שאין להם עיצוב כהה משלהם"),
    ("tabsAndHistory", "Tabs and history", "כרטיסיות והיסטוריה"),
    ("closeUnusedTabs", "Close unused tabs", "סגירת כרטיסיות שלא בשימוש"),
    ("keepHistory", "Keep history", "שמירת היסטוריה"),
    ("clearCookies", "Clear cookies and site data",
     "ניקוי קובצי Cookie ונתוני אתרים"),
    ("clearCookiesSub", "Signs you out of websites on this phone",
     "מנתק אותך מאתרים בטלפון הזה"),
    ("alwaysOn", "Always on", "תמיד פעיל"),
    ("alwaysOnSub",
     "Third-party cookies blocked. Global Privacy Control sent, telling "
     "sites not to sell or share your data. Camera, microphone and location "
     "only after you say yes to a site. No usage statistics sent from the "
     "web engine.",
     "קובצי Cookie של צד שלישי חסומים. נשלח אות Global Privacy Control, "
     "שמורה לאתרים לא למכור ולא לשתף את המידע שלך. מצלמה, מיקרופון ומיקום "
     "רק אחרי אישור שלך לאתר. מנוע הגלישה לא שולח נתוני שימוש."),
    ("credits", "Open-source credits", "קרדיטים לקוד פתוח"),
    ("creditsSub",
     "EasyList, EasyPrivacy and the EasyList Cookie List by The EasyList "
     "authors (easylist.to), used under CC BY-SA 3.0. Reader view: Mozilla "
     "Readability (Apache 2.0). QR scanner: ZXing (Apache 2.0).",
     "EasyList, EasyPrivacy ו-EasyList Cookie List מאת The EasyList authors "
     "(easylist.to), בשימוש לפי רישיון CC BY-SA 3.0. תצוגת קריאה: Mozilla "
     "Readability (Apache 2.0). סורק QR: ZXing (Apache 2.0)."),
    ("keepHistoryExplain",
     "Older pages are deleted from your history on all your devices.",
     "דפים ישנים יותר נמחקים מההיסטוריה בכל המכשירים שלך."),
    ("closeTabsExplain",
     "Tabs you haven't looked at for this long close by themselves. Private "
     "tabs always close when the app locks.",
     "כרטיסיות שלא נפתחו במשך הזמן הזה נסגרות מעצמן. כרטיסיות פרטיות "
     "נסגרות תמיד כשהאפליקציה ננעלת."),
    ("checkingBlocklist", "Checking for a newer blocklist…",
     "בודק אם יש רשימת חסימה חדשה…"),
    ("blocklistUpdated", "Blocklist updated", "רשימת החסימה עודכנה"),
    ("blocklistUpToDate", "The blocklist is up to date",
     "רשימת החסימה מעודכנת"),
    ("blocklistFailed", "Couldn't check now. Try again later.",
     "לא ניתן לבדוק עכשיו. נסו שוב מאוחר יותר."),
    ("clearCookiesTitle", "Clear cookies and site data?",
     "לנקות קובצי Cookie ונתוני אתרים?"),
    ("clearCookiesBody",
     "You will be signed out of websites on this phone. Bookmarks and "
     "history stay.",
     "החיבור שלך לאתרים בטלפון הזה ינותק. הסימניות וההיסטוריה נשארות."),
    ("cookiesCleared", "Cookies and site data cleared",
     "קובצי Cookie ונתוני אתרים נוקו"),
    ("historyNone", "Don't keep history", "לא לשמור היסטוריה"),
    ("forever", "Forever", "לתמיד"),
    ("oneWeek", "1 week", "שבוע"),
    ("oneMonth", "1 month", "חודש"),
    ("threeMonths", "3 months", "3 חודשים"),
    ("oneYear", "1 year", "שנה"),
    ("nDays", "{count} days", "{count} ימים"),
    ("never", "Never", "אף פעם"),
    ("afterDay", "After a day", "אחרי יום"),
    ("afterWeek", "After a week", "אחרי שבוע"),
    ("afterTwoWeeks", "After 2 weeks", "אחרי שבועיים"),
    ("afterMonth", "After a month", "אחרי חודש"),
    ("afterDays", "After {count} days", "אחרי {count} ימים"),
    ("searchSuggestions", "Search suggestions", "הצעות חיפוש"),
    ("searchSuggestionsOff",
     "Off: nothing you type is sent anywhere until you search.",
     "כבוי: שום דבר שמקלידים לא נשלח לשום מקום עד שמחפשים."),
    ("searchSuggestionsOn",
     "What you type in the address bar is sent to {engine} as you type. "
     "Never addresses, and never in private tabs.",
     "מה שמקלידים בשורת הכתובת נשלח אל {engine} תוך כדי הקלדה. אף פעם לא "
     "כתובות, ואף פעם לא בכרטיסיות פרטיות."),
    ("searchSuggestionsNone", "{engine} doesn't offer suggestions.",
     "{engine} לא מציע הצעות חיפוש."),
    ("searchSuggestionsAskTitle", "Turn on search suggestions?",
     "להפעיל הצעות חיפוש?"),
    ("searchSuggestionsAskBody",
     "As you type in the address bar, the letters are sent to {engine} so "
     "it can suggest searches. That tells it what you type even if you "
     "never search for it. Addresses and private tabs are never sent.",
     "תוך כדי הקלדה בשורת הכתובת, האותיות נשלחות אל {engine} כדי שיציע "
     "חיפושים. כך הוא יודע מה הקלדת גם אם לא חיפשת את זה בסוף. כתובות "
     "וכרטיסיות פרטיות לא נשלחות אף פעם."),
    ("addSearchEngine", "Add search engine", "הוספת מנוע חיפוש"),
    ("engineAddress", "Search address, with %s where the words go",
     "כתובת החיפוש, עם %s במקום מילות החיפוש"),
    ("engineInvalid", "Type a name and a web address that contains %s",
     "יש להקליד שם וכתובת אתר שמכילה %s"),
    ("removeEngine", "Remove {name}", "הסרת {name}"),
    ("language", "Language", "שפה"),
    ("languageSystem", "Phone language", "שפת הטלפון"),
    ("languageNote",
     "Sign-in and account screens are shared by all Zero-Trust apps and "
     "are in English for now.",
     "מסכי הכניסה והחשבון משותפים לכל אפליקציות Zero-Trust ומוצגים בינתיים "
     "באנגלית."),
    ("startPageSection", "Start page", "דף הפתיחה"),
    ("showMostVisited", "Show most visited sites",
     "הצגת האתרים הנצפים ביותר"),
    ("showMostVisitedSub", "From your history, on the start page",
     "מתוך ההיסטוריה שלך, בדף הפתיחה"),
    ("privacyReportSub",
     "Counts the trackers and ads blocked on each site. Kept like your "
     "history: end-to-end encrypted in your account.",
     "סופר את רכיבי המעקב והפרסומות שנחסמו בכל אתר. נשמר כמו ההיסטוריה "
     "שלך: מוצפן מקצה לקצה בחשבון שלך."),

    # ---- Privacy report ----
    ("reportWeek",
     "{count, plural, =0{Nothing blocked in the last 7 days} "
     "=1{1 tracker or ad blocked in the last 7 days} "
     "other{{count} trackers and ads blocked in the last 7 days}}",
     "{count, plural, =0{לא נחסם דבר ב-7 הימים האחרונים} "
     "=1{רכיב מעקב או פרסומת אחד נחסם ב-7 הימים האחרונים} "
     "other{{count} רכיבי מעקב ופרסומות נחסמו ב-7 הימים האחרונים}}"),
    ("reportMonth", "Last {days} days: {count}", "{days} הימים האחרונים: {count}"),
    ("reportTopSites", "Where most was blocked this week",
     "האתרים שבהם נחסם הכי הרבה השבוע"),
    ("reportEmpty",
     "Nothing counted yet. Browse a little and come back.",
     "עדיין לא נספר דבר. גלשו קצת וחזרו לכאן."),
    ("reportOff",
     "The privacy report is off. Trackers are still blocked; they just "
     "aren't counted.",
     "דוח הפרטיות כבוי. המעקב עדיין נחסם, רק לא נספר."),
    ("reportClear", "Clear report", "ניקוי הדוח"),
    ("reportCleared", "Privacy report cleared", "דוח הפרטיות נוקה"),
    ("reportNote",
     "Counted on your devices and kept end-to-end encrypted in your "
     "account, like your history. Private tabs add to the total without "
     "the name of the site.",
     "נספר במכשירים שלך ונשמר מוצפן מקצה לקצה בחשבון שלך, כמו ההיסטוריה. "
     "כרטיסיות פרטיות מוסיפות לסך הכול בלי שם האתר."),
    ("reportNoSites",
     "Site names are not kept while history is off.",
     "שמות אתרים לא נשמרים כשההיסטוריה כבויה."),
    ("reportCountOnSite", "{count} blocked", "{count} נחסמו"),

    # ---- Tabs ----
    ("newGroup", "New group", "קבוצה חדשה"),
    ("removeFromGroup", "Remove from group", "הסרה מהקבוצה"),
    ("groupName", "Group name", "שם הקבוצה"),
    ("newTabInGroup", "New tab in this group", "כרטיסייה חדשה בקבוצה הזאת"),
    ("renameGroup", "Rename group", "שינוי שם הקבוצה"),
    ("ungroupTabs", "Ungroup tabs", "פירוק הקבוצה"),
    ("closeNTabs",
     "{count, plural, =1{Close 1 tab} other{Close {count} tabs}}",
     "{count, plural, =1{סגירת כרטיסייה אחת} other{סגירת {count} כרטיסיות}}"),
    ("searchTabs", "Search tabs", "חיפוש בכרטיסיות"),
    ("stopSearching", "Stop searching", "סיום החיפוש"),
    ("closeAllPrivateTabs", "Close all private tabs",
     "סגירת כל הכרטיסיות הפרטיות"),
    ("closeAllTabs", "Close all tabs", "סגירת כל הכרטיסיות"),
    ("tabsCount", "Tabs ({count})", "כרטיסיות ({count})"),
    ("privateCount", "Private ({count})", "פרטיות ({count})"),
    ("otherDevices", "Other devices", "מכשירים אחרים"),
    ("noOpenTabs", "No open tabs", "אין כרטיסיות פתוחות"),
    ("privateTabsExplain",
     "Private tabs keep no history, and their cookies are deleted when the "
     "last one closes or the app locks.",
     "כרטיסיות פרטיות לא שומרות היסטוריה, וקובצי ה-Cookie שלהן נמחקים "
     "כשהאחרונה נסגרת או כשהאפליקציה ננעלת."),
    ("noTabsMatch", "No tabs match.", "אין כרטיסיות מתאימות."),
    ("notInGroup", "Not in a group", "לא בקבוצה"),
    ("nTabs",
     "{count, plural, =1{1 tab} other{{count} tabs}}",
     "{count, plural, =1{כרטיסייה אחת} other{{count} כרטיסיות}}"),
    ("groupOptions", "Group options", "אפשרויות הקבוצה"),
    ("closeTab", "Close tab", "סגירת הכרטיסייה"),
    ("otherDevicesEmpty",
     "Tabs open in ZT Browser on your other devices show here, end-to-end "
     "encrypted. Private tabs are never shared.",
     "כרטיסיות שפתוחות ב-ZT Browser במכשירים האחרים שלך מוצגות כאן, "
     "מוצפנות מקצה לקצה. כרטיסיות פרטיות לא משותפות אף פעם."),

    # ---- Bookmarks ----
    ("editBookmark", "Edit bookmark", "עריכת הסימנייה"),
    ("importBookmarks", "Import bookmarks", "ייבוא סימניות"),
    ("importExplain",
     "Pick the bookmarks file you exported from your other browser:\n\n"
     "• Chrome or Edge: Bookmarks > Bookmark manager > ⋮ > Export bookmarks "
     "(on a computer).\n"
     "• Firefox: Bookmarks > Manage bookmarks > Import and Backup > Export "
     "bookmarks to HTML.\n\n"
     "The file stays on this phone; the bookmarks are end-to-end encrypted "
     "in your account.",
     "בחרו את קובץ הסימניות שייצאתם מהדפדפן האחר:\n\n"
     "• Chrome או Edge: סימניות > מנהל הסימניות > ⋮ > ייצוא סימניות "
     "(במחשב).\n"
     "• Firefox: סימניות > ניהול סימניות > ייבוא וגיבוי > ייצוא סימניות "
     "ל-HTML.\n\n"
     "הקובץ נשאר בטלפון הזה; הסימניות מוצפנות מקצה לקצה בחשבון שלך."),
    ("pickFile", "Pick file", "בחירת קובץ"),
    ("noBookmarksInFile", "No bookmarks found in that file",
     "לא נמצאו סימניות בקובץ הזה"),
    ("allAlreadySaved", "All {count} bookmarks were already saved",
     "כל {count} הסימניות כבר היו שמורות"),
    ("importedCount",
     "{count, plural, =1{Imported 1 bookmark} "
     "other{Imported {count} bookmarks}}",
     "{count, plural, =1{יובאה סימנייה אחת} other{יובאו {count} סימניות}}"),
    ("searchBookmarks", "Search bookmarks", "חיפוש בסימניות"),
    ("noBookmarksYet",
     "No bookmarks yet. Tap the star in the menu to save a page. Bookmarks "
     "are end-to-end encrypted and on all your devices.",
     "עדיין אין סימניות. מקישים על הכוכב בתפריט כדי לשמור דף. הסימניות "
     "מוצפנות מקצה לקצה וזמינות בכל המכשירים שלך."),
    ("noBookmarksMatch", "No bookmarks match.", "אין סימניות מתאימות."),

    # ---- History ----
    ("daysAgo", "{count} days ago", "לפני {count} ימים"),
    ("clearHistory", "Clear history", "ניקוי היסטוריה"),
    ("historyCleared", "History cleared on all your devices",
     "ההיסטוריה נוקתה בכל המכשירים שלך"),
    ("searchHistory", "Search history", "חיפוש בהיסטוריה"),
    ("historyOff",
     "History is off. Turn it on in Settings, under Keep history.",
     "ההיסטוריה כבויה. אפשר להפעיל אותה בהגדרות, תחת שמירת היסטוריה."),
    ("historyEmpty",
     "Pages you visit show here, end-to-end encrypted. Private tabs are "
     "never saved.",
     "דפים שביקרת בהם מוצגים כאן, מוצפנים מקצה לקצה. כרטיסיות פרטיות לא "
     "נשמרות אף פעם."),
    ("nothingMatches", "Nothing matches.", "אין תוצאות מתאימות."),

    # ---- Downloads ----
    ("sizeBytes", "{count} bytes", "{count} בייטים"),
    ("fileFallbackName", "File", "קובץ"),
    ("noAppOpens", "No app on this phone opens this kind of file",
     "אין בטלפון הזה אפליקציה שפותחת קובץ מהסוג הזה"),
    ("cancelDownloadTitle", "Cancel download?", "לבטל את ההורדה?"),
    ("deleteFileTitle", "Delete file?", "למחוק את הקובץ?"),
    ("stopsDownloading", "{name} stops downloading.",
     "ההורדה של {name} תיפסק."),
    ("deletedFromPhone", "{name} is deleted from this phone.",
     "{name} יימחק מהטלפון הזה."),
    ("keep", "Keep", "להשאיר"),
    ("cancelDownload", "Cancel download", "ביטול ההורדה"),
    ("downloadsEmpty",
     "Files you download show here. They are saved in your phone's "
     "Downloads folder.",
     "קבצים שמורידים מוצגים כאן. הם נשמרים בתיקיית ההורדות של הטלפון."),
    ("progressOf", "{done} of {total}", "{done} מתוך {total}"),
    ("downloadingEllipsis", "Downloading…", "מוריד…"),
    ("waitingConnection", "Waiting for a connection", "ממתין לחיבור"),
    ("couldntDownload", "Couldn't download", "ההורדה נכשלה"),
    ("cantShare", "This file can't be shared", "אי אפשר לשתף את הקובץ הזה"),

    # ---- Reading list ----
    ("readingListError", "The reading list couldn't load.",
     "לא ניתן היה לטעון את רשימת הקריאה."),
    ("readingListEmpty",
     "Save pages from the menu with \"Add to reading list\". Articles are "
     "kept to read offline, end-to-end encrypted in your account.",
     "שומרים דפים מהתפריט עם \"הוספה לרשימת הקריאה\". מאמרים נשמרים "
     "לקריאה בלי חיבור, מוצפנים מקצה לקצה בחשבון שלך."),
    ("savedOffline", "Saved offline", "שמור לקריאה בלי חיבור"),
    ("openSavedCopy", "Open saved copy", "פתיחת העותק השמור"),
    ("markUnread", "Mark unread", "סימון כלא נקרא"),
    ("markRead", "Mark read", "סימון כנקרא"),
    ("savedCopy", "Saved copy", "עותק שמור"),

    # ---- Site permissions and the shield ----
    ("permCamera", "Camera", "מצלמה"),
    ("permMicrophone", "Microphone", "מיקרופון"),
    ("permLocation", "Location", "מיקום"),
    ("permOnHost", "{kind} on {host}", "{kind} באתר {host}"),
    ("askNextTime", "Ask next time", "לשאול בפעם הבאה"),
    ("sitePermsEmpty",
     "When a site asks for your camera, microphone or location, ZT Browser "
     "asks you first. Answers you choose to remember show here.",
     "כשאתר מבקש את המצלמה, המיקרופון או המיקום שלך, ZT Browser שואל אותך "
     "קודם. תשובות שבחרת לזכור מוצגות כאן."),
    ("permAllowedChip", "{kind}: allowed", "{kind}: מאושר"),
    ("permBlockedChip", "{kind}: blocked", "{kind}: חסום"),
    ("forget", "Forget", "שכחה"),
    ("allowed", "Allowed", "מאושר"),
    ("blocked", "Blocked", "חסום"),
    ("connectionSecure", "Connection is secure", "החיבור מאובטח"),
    ("connectionNotSecure", "Connection is not secure", "החיבור לא מאובטח"),
    ("connectionSecureSub",
     "What you send and see on this site is encrypted on the way.",
     "מה שנשלח ומוצג באתר הזה מוצפן בדרך."),
    ("connectionNotSecureSub",
     "Others on your network can see and change this page. Don't enter "
     "passwords or card numbers here.",
     "אחרים ברשת שלך יכולים לראות ולשנות את הדף הזה. אין להזין כאן סיסמאות "
     "או מספרי כרטיס."),
    ("blockedOnPage",
     "{count, plural, =1{1 tracker or ad blocked} "
     "other{{count} trackers and ads blocked}}",
     "{count, plural, =1{נחסם רכיב מעקב או פרסומת אחד} "
     "other{נחסמו {count} רכיבי מעקב ופרסומות}}"),
    ("blockedOnPageSub", "On this page, from EasyList and EasyPrivacy.",
     "בדף הזה, לפי EasyList ו-EasyPrivacy."),
    ("protectionOn", "Protection on {site}", "הגנה באתר {site}"),
    ("protectionSub", "Turn off only if the site doesn't work. It reloads.",
     "לכבות רק אם האתר לא עובד. הדף ייטען מחדש."),
    ("trackerBlockingOff", "Tracker blocking is off", "חסימת המעקב כבויה"),
    ("turnOnInSettings", "Turn it on in Settings.",
     "אפשר להפעיל אותה בהגדרות."),
    ("javascriptOn", "JavaScript on {site}", "JavaScript באתר {site}"),
    ("javascriptSub",
     "Off makes many sites simpler and harder to track you on, but some "
     "stop working. It reloads.",
     "כיבוי הופך אתרים רבים לפשוטים יותר ומקשה לעקוב אחריך, אבל חלקם "
     "מפסיקים לעבוד. הדף ייטען מחדש."),

    # ---- QR ----
    ("qrFor", "QR code for {url}", "קוד QR עבור {url}"),
    ("shareLink", "Share link", "שיתוף הקישור"),
]

INT_PLACEHOLDERS = {
    "findCount": ["active", "count"],
    "nDays": ["count"],
    "afterDays": ["count"],
    "daysAgo": ["count"],
    "allAlreadySaved": ["count"],
    "sizeBytes": ["count"],
    "tabsCount": ["count"],
    "privateCount": ["count"],
    "reportMonth": ["days", "count"],
    "reportCountOnSite": ["count"],
}


def placeholders(key, text):
    out = {}
    plural = re.findall(r"\{(\w+), plural,", text)
    for name in plural:
        out[name] = {"type": "int"}
    for name in re.findall(r"\{(\w+)\}", text):
        if name in out:
            continue
        kind = "int" if name in INT_PLACEHOLDERS.get(key, []) else "String"
        out[name] = {"type": kind}
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "lib", "l10n")
    keys = [k for k, _, _ in S]
    assert len(keys) == len(set(keys)), "duplicate key"
    en = {"@@locale": "en"}
    he = {"@@locale": "he"}
    for key, english, hebrew in S:
        en[key] = english
        ph = placeholders(key, english)
        assert ph.keys() == placeholders(key, hebrew).keys(), key
        if ph:
            en["@" + key] = {"placeholders": ph}
        he[key] = hebrew
    for name, data in (("app_en.arb", en), ("app_he.arb", he)):
        with open(os.path.join(out, name), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
    print(len(S), "texts")


if __name__ == "__main__":
    main()
